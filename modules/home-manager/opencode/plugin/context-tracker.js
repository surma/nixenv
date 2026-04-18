export const ContextTracker = async ({ client, directory }) => {
  const contextLimits = {} // { "providerID:modelID": number }
  const lastUsage = {} // { sessionID: { used, providerID, modelID } }
  let limitsLoaded = false

  // Fetch provider context limits. Returns a promise so callers can optionally
  // await it. Must not be awaited during plugin init — the server cannot serve
  // HTTP while init is in progress, so an SDK call there would deadlock.
  let limitsPromise = null
  function fetchLimits() {
    if (limitsLoaded) return Promise.resolve()
    if (limitsPromise) return limitsPromise
    limitsPromise = client.config
      .providers({ query: { directory }, throwOnError: true })
      .then((resp) => {
        for (const provider of resp.data.providers) {
          for (const [modelID, model] of Object.entries(provider.models)) {
            if (model?.limit?.context) {
              contextLimits[`${provider.id}:${modelID}`] = model.limit.context
            }
          }
        }
        limitsLoaded = true
      })
      .catch(() => {
        limitsPromise = null // allow retry
      })
    return limitsPromise
  }

  // Seed the usage cache from session history. Called from hooks when we have
  // no cached data (e.g. after a restart into a resumed session).
  async function seedUsage(sessionID) {
    try {
      const resp = await client.session.messages({
        path: { id: sessionID },
        query: { directory },
        throwOnError: true,
      })
      const lastAssistant = [...resp.data]
        .reverse()
        .find((m) => m.info.role === "assistant")
      if (lastAssistant && lastAssistant.info.role === "assistant") {
        const info = lastAssistant.info
        lastUsage[sessionID] = {
          used: info.tokens.input + (info.tokens.cache?.read ?? 0),
          providerID: info.providerID,
          modelID: info.modelID,
        }
        await fetchLimits()
      }
    } catch {
      // Non-fatal — tag will show "no data yet".
    }
  }

  function usageTag(sessionID) {
    const now = new Date().toISOString()
    const usage = lastUsage[sessionID]
    if (!usage) {
      return `<system-reminder>[${now} | context: no data yet]</system-reminder>`
    }
    const size = contextLimits[`${usage.providerID}:${usage.modelID}`]
    if (!size) {
      return `<system-reminder>[${now} | context: ${usage.used} tokens, limit unknown]</system-reminder>`
    }
    const pct = ((usage.used / size) * 100).toFixed(1)
    return `<system-reminder>[${now} | context: ${pct}% (${usage.used}/${size})]</system-reminder>`
  }

  return {
    event: async ({ event }) => {
      if (event.type !== "message.updated") return
      const info = event.properties.info
      if (info.role !== "assistant") return
      fetchLimits()
      lastUsage[info.sessionID] = {
        used: info.tokens.input + (info.tokens.cache?.read ?? 0),
        providerID: info.providerID,
        modelID: info.modelID,
      }
    },

    "tool.execute.after": async (_input, output) => {
      if (!lastUsage[_input.sessionID]) await seedUsage(_input.sessionID)
      const tag = usageTag(_input.sessionID)
      output.output = `${output.output}\n\n${tag}`
    },

    "chat.message": async (input, output) => {
      if (!lastUsage[input.sessionID]) await seedUsage(input.sessionID)
      const tag = usageTag(input.sessionID)
      const last = [...output.parts].reverse().find((p) => p.type === "text")
      if (last) {
        last.text += `\n\n${tag}`
      }
    },
  }
}
