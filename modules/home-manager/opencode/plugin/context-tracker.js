export const ContextTracker = async ({ client, directory }) => {
  async function usageTag(sessionID) {
    const now = new Date().toISOString()
    try {
      const resp = await client.session.messages({
        path: { id: sessionID },
        query: { directory },
        throwOnError: true,
      })

      const lastAssistant = [...resp.data]
        .reverse()
        .find((m) => m.info.role === "assistant")

      if (!lastAssistant || lastAssistant.info.role !== "assistant") {
        return `<system-reminder>[${now} | context: no data yet]</system-reminder>`
      }

      const msg = lastAssistant.info
      const used = msg.tokens.input + (msg.tokens.cache?.read ?? 0)

      const provResp = await client.config.providers({
        query: { directory },
        throwOnError: true,
      })

      const provider = provResp.data.providers.find(
        (p) => p.id === msg.providerID,
      )
      const model = provider?.models[msg.modelID]
      const size = model?.limit?.context

      if (!size) {
        return `<system-reminder>[${now} | context: ${used} tokens, limit unknown]</system-reminder>`
      }

      const pct = ((used / size) * 100).toFixed(1)
      return `<system-reminder>[${now} | context: ${pct}% (${used}/${size})]</system-reminder>`
    } catch {
      return `<system-reminder>[${now} | context: unavailable]</system-reminder>`
    }
  }

  return {
    "tool.execute.after": async (input, output) => {
      const tag = await usageTag(input.sessionID)
      output.output = `${output.output}\n\n${tag}`
    },

    "chat.message": async (input, output) => {
      const tag = await usageTag(input.sessionID)
      output.parts.push({ type: "text", text: `\n\n${tag}` })
    },
  }
}
