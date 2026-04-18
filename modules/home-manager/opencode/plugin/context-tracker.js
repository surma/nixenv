export const ContextTracker = async ({ client, directory }) => {
  // Cache: populated lazily and from events — never block init or hooks.
  const contextLimits = {} // { "providerID:modelID": number }
  const lastUsage = {} // { sessionID: { used, providerID, modelID } }
  let limitsLoaded = false

  // Fetch provider context limits in the background. Must not await during
  // plugin init — the server cannot serve HTTP while plugin init is in progress,
  // so an SDK call here would deadlock.
  function fetchLimits() {
    if (limitsLoaded) return
    limitsLoaded = true // prevent duplicate fetches
    client.config
      .providers({ query: { directory }, throwOnError: true })
      .then((resp) => {
        for (const provider of resp.data.providers) {
          for (const [modelID, model] of Object.entries(provider.models)) {
            if (model?.limit?.context) {
              contextLimits[`${provider.id}:${modelID}`] = model.limit.context
            }
          }
        }
      })
      .catch(() => {
        limitsLoaded = false // allow retry on next event
      })
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
      fetchLimits() // trigger background fetch on first assistant message
      lastUsage[info.sessionID] = {
        used: info.tokens.input + (info.tokens.cache?.read ?? 0),
        providerID: info.providerID,
        modelID: info.modelID,
      }
    },

    "tool.execute.after": async (_input, output) => {
      const tag = usageTag(_input.sessionID)
      output.output = `${output.output}\n\n${tag}`
    },

    "chat.message": async (input, output) => {
      const tag = usageTag(input.sessionID)
      // Append to the last text part rather than pushing a new one.
      // output.parts contains full Part objects with required id/sessionID/messageID
      // fields — pushing a bare {type, text} object fails validation.
      const last = [...output.parts].reverse().find((p) => p.type === "text")
      if (last) {
        last.text += `\n\n${tag}`
      }
    },
  }
}
