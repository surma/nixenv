import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { Key } from "@mariozechner/pi-tui";

const STATE_ENTRY = "claude-plan-mode";

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

**Plan Guidelines:** The plan should contain only your final recommended approach, not all alternatives considered. Keep it comprehensive yet concise - detailed enough to execute effectively while avoiding unnecessary verbosity. Start the plan with a short **Summary** section that restates the user's request/problem in your own words. Include a **Key Context** section (or bullets) that captures important findings from research (relevant files, constraints, commands, assumptions) so the implementation phase retains the necessary grounding after history reset.

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
- Ensure the plan is coherent, ordered, and includes a summary of the goal, key context from research, files to change, risks, and tests.

### Phase 5: Call exit_plan_mode
- End your turn either by asking the user a question or by calling exit_plan_mode with the full plan.

---

## Current Draft Plan
${planBody}
</system-reminder>`;
}

function buildPlanModeReminder(): string {
	return `[PLAN MODE ACTIVE]
You are in plan mode. Focus on research and drafting the plan only (no implementation or file edits).
Include Summary and Key Context sections in the plan. Call exit_plan_mode with the full plan when ready.`;
}

export default function claudePlanMode(pi: ExtensionAPI): void {
	let planModeEnabled = false;
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
		updateStatus(ctx);
		persistState();
		if (ctx.hasUI) {
			ctx.ui.notify("Plan mode enabled. Gather context and draft the plan in chat.", "info");
		}
	}

	function disablePlanMode(ctx: ExtensionContext): void {
		if (!planModeEnabled) return;
		planModeEnabled = false;
		updateStatus(ctx);
		persistState();
		if (ctx.hasUI) {
			ctx.ui.notify("Plan mode disabled.", "info");
		}
	}

	function queuePlanAcceptance(): void {
		pi.sendUserMessage("/plan accept", { deliverAs: "steer" });
	}

	function queuePlanRejection(): void {
		// Intentionally left blank: avoid auto-follow-up so the user can respond manually.
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

			const planStoredResponse = () => {
				queuePlanRejection();
				return {
					content: [
						{
							type: "text",
							text: "Plan stored. Provide feedback or keep refining the plan, then call exit_plan_mode again.",
						},
					],
					details: { approved: false },
				};
			};

			const reviewedPlan = await ctx.ui.editor("Review plan (edit if needed):", plan);
			if (reviewedPlan === undefined) {
				currentPlan = plan;
				return planStoredResponse();
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
			const approvedPlan = reviewedPlan;
			const choice = await ctx.ui.select("Plan ready. Start implementation session?", [
				"Yes, start implementation session",
				"No, keep planning",
			]);

			if (!choice || choice.startsWith("No")) {
				return planStoredResponse();
			}

			disablePlanMode(ctx);
			queuePlanAcceptance();
			return {
				content: [
					{
						type: "text",
						text: `Plan approved. Starting a new session with the plan:\n\n${approvedPlan}`,
					},
				],
				details: { approved: true },
			};
		},
	});

	pi.on("context", async (event) => {
		if (planModeEnabled) return;

		return {
			messages: event.messages.filter((message) => {
				const msg = message as { role?: string; customType?: string };
				return !(msg.role === "custom" && msg.customType === "plan-mode-reminder");
			}),
		};
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!planModeEnabled) return;
		const planModePrompt = buildPlanModeSystemPrompt(currentPlan);
		const planModeReminder = buildPlanModeReminder();

		return {
			systemPrompt: `${event.systemPrompt}\n\n${planModePrompt}`,
			message: {
				customType: "plan-mode-reminder",
				content: planModeReminder,
				display: false,
			},
		};
	});

	pi.on("session_start", async (_event, ctx) => {
		const entries = ctx.sessionManager.getEntries();
		const lastState = entries
			.filter((entry) => entry.type === "custom" && entry.customType === STATE_ENTRY)
			.pop() as { data?: { enabled?: boolean } } | undefined;

		currentPlan = null;

		if (lastState?.data?.enabled) {
			planModeEnabled = true;
		}

		updateStatus(ctx);
	});
}
