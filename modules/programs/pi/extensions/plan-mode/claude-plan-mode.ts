import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { Key } from "@mariozechner/pi-tui";
import { promises as fs } from "node:fs";
import * as path from "node:path";

const PLAN_MODE_TOOLS = ["read", "bash", "edit", "write", "grep", "find", "ls", "exit_plan_mode"];
const DEFAULT_TOOLS = ["read", "bash", "edit", "write"];
const STATE_ENTRY = "claude-plan-mode";

type AllowListEntry = { type: "exact"; value: string } | { type: "regex"; value: string };

const STATE_DIR = process.env.XDG_STATE_HOME ?? (process.env.HOME ? `${process.env.HOME}/.local/state` : null);
const STATE_PATH = STATE_DIR ? path.join(STATE_DIR, "pi/claude-plan-mode/state.json") : null;

let allowList: AllowListEntry[] = [];

function normalizeAllowList(value: unknown): AllowListEntry[] {
	if (!Array.isArray(value)) return [];
	return value.flatMap((entry) => {
		if (!entry || typeof entry !== "object") return [];
		const candidate = entry as { type?: unknown; value?: unknown };
		if ((candidate.type === "exact" || candidate.type === "regex") && typeof candidate.value === "string") {
			return [{ type: candidate.type, value: candidate.value }];
		}
		return [];
	});
}

async function loadAllowList(ctx?: ExtensionContext): Promise<void> {
	if (!STATE_PATH) return;
	try {
		const raw = await fs.readFile(STATE_PATH, "utf8");
		const parsed = JSON.parse(raw) as { allowlist?: unknown };
		allowList = normalizeAllowList(parsed.allowlist);
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") {
			allowList = [];
			return;
		}
		if (ctx?.hasUI) {
			ctx.ui.notify("Failed to load plan-mode allowlist.", "error");
		}
	}
}

async function saveAllowList(ctx?: ExtensionContext): Promise<void> {
	if (!STATE_PATH) return;
	try {
		await fs.mkdir(path.dirname(STATE_PATH), { recursive: true });
		await fs.writeFile(STATE_PATH, JSON.stringify({ allowlist: allowList }, null, 2));
	} catch {
		if (ctx?.hasUI) {
			ctx.ui.notify("Failed to save plan-mode allowlist.", "error");
		}
	}
}

function addAllowListEntry(entry: AllowListEntry): void {
	if (!allowList.some((existing) => existing.type === entry.type && existing.value === entry.value)) {
		allowList = [...allowList, entry];
	}
}

function isAllowListed(command: string): boolean {
	return allowList.some((entry) => {
		if (entry.type === "exact") {
			return entry.value === command;
		}
		if (entry.type === "regex") {
			try {
				return new RegExp(entry.value).test(command);
			} catch {
				return false;
			}
		}
		return false;
	});
}

const DESTRUCTIVE_PATTERNS = [
	/\brm\b/i,
	/\brmdir\b/i,
	/\bmv\b/i,
	/\bcp\b/i,
	/\bmkdir\b/i,
	/\btouch\b/i,
	/\bchmod\b/i,
	/\bchown\b/i,
	/\bchgrp\b/i,
	/\bln\b/i,
	/\btee\b/i,
	/\btruncate\b/i,
	/\bdd\b/i,
	/\bshred\b/i,
	/(^|[^<])>(?!>)/,
	/>>/,
	/\bnpm\s+(install|uninstall|update|ci|link|publish)/i,
	/\byarn\s+(add|remove|install|publish)/i,
	/\bpnpm\s+(add|remove|install|publish)/i,
	/\bpip\s+(install|uninstall)/i,
	/\bapt(-get)?\s+(install|remove|purge|update|upgrade)/i,
	/\bbrew\s+(install|uninstall|upgrade)/i,
	/\bgit\s+(add|commit|push|pull|merge|rebase|reset|checkout|branch\s+-[dD]|stash|cherry-pick|revert|tag|init|clone)/i,
	/\bsudo\b/i,
	/\bsu\b/i,
	/\bkill\b/i,
	/\bpkill\b/i,
	/\bkillall\b/i,
	/\breboot\b/i,
	/\bshutdown\b/i,
	/\bsystemctl\s+(start|stop|restart|enable|disable)/i,
	/\bservice\s+\S+\s+(start|stop|restart)/i,
	/\b(vim?|nano|emacs|code|subl)\b/i,
];

const SAFE_PATTERNS = [
	/^\s*cat\b/,
	/^\s*head\b/,
	/^\s*tail\b/,
	/^\s*less\b/,
	/^\s*more\b/,
	/^\s*grep\b/,
	/^\s*find\b/,
	/^\s*ls\b/,
	/^\s*pwd\b/,
	/^\s*echo\b/,
	/^\s*printf\b/,
	/^\s*wc\b/,
	/^\s*sort\b/,
	/^\s*uniq\b/,
	/^\s*diff\b/,
	/^\s*file\b/,
	/^\s*stat\b/,
	/^\s*du\b/,
	/^\s*df\b/,
	/^\s*tree\b/,
	/^\s*which\b/,
	/^\s*whereis\b/,
	/^\s*type\b/,
	/^\s*env\b/,
	/^\s*printenv\b/,
	/^\s*uname\b/,
	/^\s*whoami\b/,
	/^\s*id\b/,
	/^\s*date\b/,
	/^\s*cal\b/,
	/^\s*uptime\b/,
	/^\s*ps\b/,
	/^\s*top\b/,
	/^\s*htop\b/,
	/^\s*free\b/,
	/^\s*git\s+(status|log|diff|show|branch|remote|config\s+--get)/i,
	/^\s*git\s+ls-/i,
	/^\s*npm\s+(list|ls|view|info|search|outdated|audit)/i,
	/^\s*yarn\s+(list|info|why|audit)/i,
	/^\s*node\s+--version/i,
	/^\s*python\s+--version/i,
	/^\s*curl\s/i,
	/^\s*wget\s+-O\s*-/i,
	/^\s*jq\b/,
	/^\s*sed\s+-n/i,
	/^\s*awk\b/,
	/^\s*rg\b/,
	/^\s*fd\b/,
	/^\s*bat\b/,
	/^\s*exa\b/,
];

function isSafeCommand(command: string): boolean {
	const isDestructive = DESTRUCTIVE_PATTERNS.some((pattern) => pattern.test(command));
	const isSafe = SAFE_PATTERNS.some((pattern) => pattern.test(command));
	return !isDestructive && isSafe;
}

function buildPlanModeSystemPrompt(plan: string | null): string {
	const trimmedPlan = plan?.trim();
	const planBody = trimmedPlan && trimmedPlan.length > 0 ? trimmedPlan : "No plan drafted yet.";

	return `<system-reminder>
# Plan Mode - System Reminder

CRITICAL: Plan mode ACTIVE. Your primary job is to produce a high-quality plan.
To do that, you should frontload research and gather as much context as possible.
Use tools freely to inspect code, search, curl docs, and run small experiments.

Writing to files is allowed when it supports research or experiments (prefer temp
or scratch locations). Do NOT make lasting or destructive changes to the project's
source code, configs, or system state (no commits, package installs, or destructive
commands against the repo). Focus on observation, analysis, and planning.

If a command seems useful and non-destructive, run it—do not assume it is forbidden.
If the tool requires permission, the user will be prompted.

---

## Responsibility

Your current responsibility is to think, read, search, and construct a well-formed plan that accomplishes the goal the user wants to achieve. Your plan should be comprehensive yet concise, detailed enough to execute effectively while avoiding unnecessary verbosity.

Ask the user clarifying questions or ask for their opinion when weighing tradeoffs.

**NOTE:** At any point in time through this workflow you should feel free to ask the user questions or clarifications. Don't make large assumptions about user intent. The goal is to present a well researched plan to the user, and tie any loose ends before implementation begins.

---

## Important

The user indicated that they do not want implementation yet. Avoid changing project files or system state. You may run tools for research and temporary experiments, but keep writes confined to scratch locations and avoid altering the repo. This supersedes any other instructions you have received.

---

## Plan Storage (In-Memory)

No plan file is used. Maintain a single cohesive plan in the conversation and update it as you refine. When the plan is ready, call exit_plan_mode with the full plan to request approval.

**Plan Guidelines:** The plan should contain only your final recommended approach, not all alternatives considered. Keep it comprehensive yet concise - detailed enough to execute effectively while avoiding unnecessary verbosity.

---

## Enhanced Planning Workflow

### Phase 1: Initial Understanding
- Understand the user's request thoroughly.
- Use tools to gather context (read code, search, curl docs, run experiments).
- Ask clarifying questions when needed.

### Phase 2: Planning
- Draft a detailed plan that addresses the goal and constraints.

### Phase 3: Synthesis
- Weigh tradeoffs, ask the user for input, and refine the plan.

### Phase 4: Final Plan
- Ensure the plan is coherent, ordered, and includes files to change, risks, and tests.

### Phase 5: Call exit_plan_mode
- End your turn either by asking the user a question or by calling exit_plan_mode with the full plan.

---

## Current Draft Plan
${planBody}
</system-reminder>`;
}

export default function claudePlanMode(pi: ExtensionAPI): void {
	let planModeEnabled = false;
	let normalTools = DEFAULT_TOOLS;
	let currentPlan: string | null = null;

	function updateStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		if (planModeEnabled) {
			ctx.ui.setStatus("plan-mode", ctx.ui.theme.fg("warning", "⏸ plan"));
		} else {
			ctx.ui.setStatus("plan-mode", undefined);
		}
	}

	function persistState(): void {
		pi.appendEntry(STATE_ENTRY, { enabled: planModeEnabled });
	}

	async function enablePlanMode(ctx: ExtensionContext): Promise<void> {
		if (planModeEnabled) return;
		planModeEnabled = true;
		normalTools = pi.getActiveTools();
		pi.setActiveTools(PLAN_MODE_TOOLS);
		updateStatus(ctx);
		persistState();
		if (ctx.hasUI) {
			ctx.ui.notify("Plan mode enabled. Gather context and draft the plan in chat.", "info");
		}
	}

	function disablePlanMode(ctx: ExtensionContext): void {
		if (!planModeEnabled) return;
		planModeEnabled = false;
		pi.setActiveTools(normalTools.length > 0 ? normalTools : DEFAULT_TOOLS);
		updateStatus(ctx);
		persistState();
		if (ctx.hasUI) {
			ctx.ui.notify("Plan mode disabled. Full tool access restored.", "info");
		}
	}

	function queuePlanAcceptance(): void {
		pi.sendUserMessage("/plan accept", { deliverAs: "steer" });
	}

	async function acceptPlan(ctx: ExtensionCommandContext): Promise<void> {
		const plan = currentPlan?.trim() ?? "";
		if (!plan) {
			ctx.ui.notify("No plan available. Ask the agent to call exit_plan_mode with a plan first.", "error");
			return;
		}

		disablePlanMode(ctx);
		const newSessionResult = await ctx.newSession();
		if (newSessionResult.cancelled) {
			ctx.ui.notify("New session cancelled.", "info");
			return;
		}

		currentPlan = null;
		ctx.ui.notify("Starting a new session with the approved plan.", "info");
		pi.sendUserMessage(plan);
	}

	pi.registerCommand("plan", {
		description: "Toggle plan mode or view the current plan",
		handler: async (args, ctx) => {
			const trimmed = args?.trim() ?? "";
			const command = trimmed.split(/\s+/)[0];

			if (command === "accept") {
				await acceptPlan(ctx);
				return;
			}

			if (!ctx.hasUI) {
				if (!planModeEnabled) {
					await enablePlanMode(ctx);
				} else {
					disablePlanMode(ctx);
				}
				return;
			}

			if (!planModeEnabled) {
				if (command === "off" || command === "disable") {
					ctx.ui.notify("Plan mode is already disabled.", "info");
					return;
				}
				await enablePlanMode(ctx);
				return;
			}

			if (!command || command === "toggle" || command === "off" || command === "disable") {
				disablePlanMode(ctx);
				return;
			}

			if (command === "on" || command === "enable") {
				ctx.ui.notify("Plan mode is already enabled.", "info");
				return;
			}

			if (command === "open" || command === "edit") {
				const updatedPlan = await ctx.ui.editor("Edit plan:", currentPlan ?? "");
				if (updatedPlan !== undefined) {
					currentPlan = updatedPlan;
					ctx.ui.notify("Plan updated.", "info");
				}
				return;
			}

			if (command === "show" || command === "status") {
				const planText = currentPlan?.trim();
				ctx.ui.notify(planText ? `Current plan:\n${planText}` : "No plan drafted yet.", "info");
				return;
			}

			const planText = currentPlan?.trim();
			ctx.ui.notify(planText ? `Current plan:\n${planText}` : "No plan drafted yet.", "info");

		},
	});

	pi.registerShortcut(Key.ctrlAlt("p"), {
		description: "Toggle plan mode",
		handler: async (ctx) => {
			if (planModeEnabled) {
				disablePlanMode(ctx);
				return;
			}
			await enablePlanMode(ctx);
		},
	});

	pi.registerTool({
		name: "exit_plan_mode",
		label: "Exit Plan Mode",
		description:
			"Request approval to exit plan mode and begin implementation. Provide the full plan for review.",
		parameters: Type.Object({
			plan: Type.String({ description: "The full implementation plan." }),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const plan = params.plan?.trim() ?? "";
			if (!plan) {
				return {
					content: [
						{
							type: "text",
							text: "No plan provided. Call exit_plan_mode again with the full plan.",
						},
					],
					details: { approved: false },
				};
			}

			currentPlan = plan;

			if (!ctx.hasUI) {
				disablePlanMode(ctx);
				return {
					content: [
						{
							type: "text",
							text: `Plan approved (non-interactive). You can now implement it.\n\nPlan:\n${plan}`,
						},
					],
					details: { approved: true },
				};
			}

			const reviewedPlan = await ctx.ui.editor("Review plan (edit if needed):", plan);
			if (reviewedPlan === undefined) {
				return {
					content: [
						{
							type: "text",
							text: "Plan review cancelled. Plan mode still active.",
						},
					],
					details: { approved: false },
				};
			}

			const normalizedPlan = reviewedPlan.trim();
			if (!normalizedPlan) {
				currentPlan = reviewedPlan;
				return {
					content: [
						{
							type: "text",
							text: "Plan is empty after review. Provide a plan and call exit_plan_mode again.",
						},
					],
					details: { approved: false },
				};
			}

			currentPlan = reviewedPlan;
			const choice = await ctx.ui.select("Plan ready. Start implementation session?", [
				"Yes, start implementation session",
				"No, keep planning",
			]);

			if (!choice || choice.startsWith("No")) {
				return {
					content: [
						{
							type: "text",
							text: "Plan stored. Provide feedback or keep refining the plan, then call exit_plan_mode again.",
						},
					],
					details: { approved: false },
				};
			}

			disablePlanMode(ctx);
			queuePlanAcceptance();
			return {
				content: [
					{
						type: "text",
						text: `Plan approved. Starting a new session with the plan:\n\n${plan}`,
					},
				],
				details: { approved: true },
			};
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!planModeEnabled) return;

		if (event.toolName === "bash") {
			const command = (event.input.command as string) ?? "";
			const normalizedCommand = command.trim();

			if (isSafeCommand(normalizedCommand) || isAllowListed(normalizedCommand)) {
				return;
			}

			if (!ctx.hasUI) {
				return {
					block: true,
					reason: `Plan mode: command blocked (no UI permission prompt available).\nCommand: ${normalizedCommand}`
				};
			}

			const choice = await ctx.ui.select("Plan mode - allow command?", [
				"no",
				"yes (this once)",
				"yes (forever)",
			]);

			if (!choice || choice === "no") {
				return {
					block: true,
					reason: `Plan mode: command blocked by user.\nCommand: ${normalizedCommand}`
				};
			}

			if (choice === "yes (this once)") {
				return;
			}

			const scope = await ctx.ui.select("Allow exact command or pattern?", ["exact", "pattern"]);
			if (!scope) {
				return {
					block: true,
					reason: `Plan mode: command blocked by user.\nCommand: ${normalizedCommand}`
				};
			}

			if (scope === "exact") {
				addAllowListEntry({ type: "exact", value: normalizedCommand });
				await saveAllowList(ctx);
				return;
			}

			const pattern = await ctx.ui.input("Regex pattern (JavaScript):", normalizedCommand);
			if (!pattern || !pattern.trim()) {
				ctx.ui.notify("No pattern provided. Command blocked.", "info");
				return {
					block: true,
					reason: `Plan mode: command blocked by user.\nCommand: ${normalizedCommand}`
				};
			}

			try {
				new RegExp(pattern);
			} catch {
				ctx.ui.notify("Invalid regex pattern. Command blocked.", "error");
				return {
					block: true,
					reason: `Plan mode: invalid regex pattern.\nCommand: ${normalizedCommand}`
				};
			}

			addAllowListEntry({ type: "regex", value: pattern });
			await saveAllowList(ctx);
			return;
		}

	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!planModeEnabled) return;
		const planModePrompt = buildPlanModeSystemPrompt(currentPlan);

		return {
			systemPrompt: `${event.systemPrompt}\n\n${planModePrompt}`,
		};
	});

	pi.on("session_start", async (_event, ctx) => {
		await loadAllowList(ctx);
		const entries = ctx.sessionManager.getEntries();
		const lastState = entries
			.filter((entry) => entry.type === "custom" && entry.customType === STATE_ENTRY)
			.pop() as { data?: { enabled?: boolean } } | undefined;

		currentPlan = null;

		if (lastState?.data?.enabled) {
			planModeEnabled = true;
			normalTools = pi.getActiveTools();
			pi.setActiveTools(PLAN_MODE_TOOLS);
		}

		updateStatus(ctx);
	});
}
