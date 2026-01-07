export const NotificationPlugin = async ({ client, $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const session = await client.session.get({
          path: { id: event.properties.sessionID },
        })
        if (!session.data?.parentID) {
          await $`noti "OpenCode is done coding"`
        }
      }
    },
  }
}
