export const NotificationPlugin = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        await $`noti "OpenCode is done coding"`
      }
    },
  }
}
