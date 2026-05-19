import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

/**
 * Context-usage awareness extension.
 *
 * On each turn, checks the context window utilisation and injects a
 * system-level note into the prompt when usage crosses configurable
 * thresholds.  This nudges the agent to wrap up, summarise, and yield
 * before the context window is exhausted.
 */

const THRESHOLDS = [
  { pct: 90, msg: "You have used {pct}% of your context window ({tokens}/{window} tokens). Wrap up immediately: summarise what you've done and what remains, then yield to the user." },
  { pct: 75, msg: "You have used {pct}% of your context window ({tokens}/{window} tokens). Start looking for a good stopping point. Summarise progress and yield soon." },
  { pct: 50, msg: "You have used {pct}% of your context window ({tokens}/{window} tokens). Be aware of your remaining capacity." },
];

export default function contextUsageExtension(pi: ExtensionAPI) {
  pi.on("before_agent_start", async (_ev) => {
    const usage = pi.getContextUsage();
    if (!usage || usage.percent == null) return;

    const pct = Math.round(usage.percent);

    // Find the highest threshold that has been exceeded.
    const threshold = THRESHOLDS.find((t) => pct >= t.pct);
    if (!threshold) return;

    const note = threshold.msg
      .replace("{pct}", String(pct))
      .replace("{tokens}", String(usage.tokens ?? "?"))
      .replace("{window}", String(usage.contextWindow));

    return {
      message: {
        customType: "context_usage_warning",
        content: [{ type: "text", text: `<context-usage>\n${note}\n</context-usage>` }],
        display: "hidden",
      },
    };
  });
}
