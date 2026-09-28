---
name: subagent
description: >-
  Run subagents in Herdr: start other coding agents in their own Herdr tabs, hand them bounded
  tasks without blocking, let them wake you when they finish, and close them. Use this skill
  whenever the user asks you to delegate, orchestrate, hand off, parallelize, or fan out work,
  or to get a second opinion or a review from another agent or model; whenever the user
  mentions a subagent, sub-agent, executor, or worker agent; and whenever you decide on your
  own to start another agent. Use it instead of any built-in subagent or task tool of your
  harness. It loads the `herdr` skill and adds the delegation pattern on top of it.
compatibility: >-
  Requires the `herdr` CLI in PATH inside a Herdr-managed pane (HERDR_ENV=1), `jq`, and the
  `orchestrator` skill.
---

# Subagents

A subagent is another coding agent that you start to take a bounded task. Subagents run in
Herdr, each in its own tab. Use Herdr for every subagent, never an in-process subagent or task
tool of your harness: a pane is visible to the user, steerable, resumable for rework, and
outlives your turn.

This skill covers only the delegation mechanism. **Load the `orchestrator` skill too**, if you
have not yet. It decides what to delegate, to which role and model, how to brief the task, and
how to accept the result. Like that skill, this one calls a subagent an *executor*.

First, confirm you are inside Herdr:

```bash
test "${HERDR_ENV:-}" = 1 && printf '%s %s %s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

If that fails, say so and stop. Do not control a Herdr session you are not in, and do not fall
back to another subagent mechanism.

**Then load the `herdr` skill before issuing any other Herdr command.** It is generated from
the installed binary, so it is the current truth about the CLI, and this skill only adds the
delegation pattern on top of it. Loading it once costs less than the `--help` spelunking you
will otherwise do halfway through the run, and it covers what this file does not: read sources,
the agent lifecycle states, key names, worktrees, and the safety rules. Where the two skills
disagree, follow this one: the `herdr` skill defaults to a split pane and to
`agent prompt --wait`, but here each executor gets a tab, and you never block.

## Setup, once per session

Create the board first, as the `orchestrator` skill says. Then name yourself so executors can
reach you, and write the standing wake rule next to the board:

```bash
herdr agent rename "$HERDR_PANE_ID" "orch-$HERDR_WORKSPACE_ID"
herdr pane rename "$HERDR_PANE_ID" "orchestrator"

# the standing reporting rule, given to every executor as system prompt; name yourself literally
cat > "$BOARD_DIR/wake.md" <<'EOF'
## Reporting to the orchestrator

When a task of yours ends — finished, blocked, or abandoned — your last act is to run this
command, with the real task id, status, and absolute report path:

    herdr agent prompt orch-w2 "<id> READY_FOR_REVIEW|BLOCKED|NEEDS_INPUT · <report path>"

Run it as a command and show its JSON result. Writing that line into your answer sends nothing:
the orchestrator never reads your answer, only what this command types into its pane. Your turn
is not finished until the result says `agent_prompted`. If it says `agent_not_found`, find the
orchestrator in `herdr agent list` and send it once more. Never hide the error with `2>/dev/null`,
and never chain this command to the report write with `&&` — a failed wake would be reported as a
failed report.
EOF
```

Agent names are unique across the whole Herdr server, not per workspace, so the bare word
`orchestrator` belongs to whichever session claimed it first — on some other project, possibly
days ago. Asking for it a second time fails with `agent_name_taken`, and the error names the pane
that holds it. Derive your name from the workspace instead: one workspace is one orchestrator, so
`orch-$HERDR_WORKSPACE_ID` cannot collide, and you can recompute it in any later turn. That
string is your wake target, and every brief you write must carry it literally. The pane label
is cosmetic and may say whatever the user wants. Put the name in the board header too, so it
stays visible: `orchestrator: orch-w2`.

## Starting an executor

**One executor is one tab in your workspace**, unless the user asks for a different layout. A
split shrinks every pane including yours, and the user reads your output in theirs; a tab is
full-window and the session stays legible at any executor count. Keep the whole run in one
workspace so the user switches tabs rather than hunting workspaces — the exception is a
worktree, which comes with its own workspace by construction.

An executor that shares the current tree gets a tab beside yours:

```bash
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "T3 docs sweep" --no-focus \
  | jq -r '.result.root_pane.pane_id'
```

An executor in a separate worktree — the `orchestrator` skill says when — gets it from
`herdr worktree create`:

```bash
herdr worktree create --branch wip/docs --base main --label docs --no-focus \
  | jq -r '.result.root_pane.pane_id, .result.worktree.path, .result.workspace.workspace_id'
```

That one call creates the branch, the checkout, a workspace, and a shell pane — you need the
returned pane id to start the agent, so you make this call yourself. Link the board into the
new tree (`.result.worktree.path`) before dispatching, as the `orchestrator` skill says.

Then start the agent with its role, and label the pane for the human. `<provider/model>` is the
model that you resolved from the roster:

```bash
ROLE=~/.agents/roster/engineer
herdr agent start eng-docs --kind pi --pane w2:p1 -- \
  --model <provider/model> --thinking "$(jq -r .thinking "$ROLE/meta.json")" \
  --append-system-prompt "$ROLE/system_prompt.md" --append-system-prompt "$BOARD_DIR/wake.md"
herdr pane rename w2:p1 "eng-docs · T3 docs sweep"
```

The wake rule goes into the executor's **system prompt**, not only into its brief. The executor
reads the brief into its conversation, and compaction rewrites the conversation: on a long task
the closing instruction is the first thing summarized away, and a rework prompt hours later
rarely repeats it. The system prompt sits outside that history and applies to every turn the
executor ever takes. `pi` and `claude` accept `--append-system-prompt` with text or a file path;
check `herdr agent` for the flags of the kind the user chose, and if it has no equivalent, repeat
the wake rule in every prompt you send that executor.

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique across the Herdr server. Choose a
name for the stream, not `agent1`. If `agent start` fails with `agent_name_taken`, choose another
name. `agent start` blocks until the agent is interactive, up to 30 s — that is the only blocking
call you are allowed.

## Dispatch without blocking

Write the brief as the `orchestrator` skill says, then send a one-line prompt that points to it:

```bash
herdr agent prompt eng-docs "T3: read your brief at $BOARD_DIR/T3.brief.md and do it."
herdr agent wait eng-docs --until working --timeout 10000
```

Send the prompt **without `--wait`**, then confirm the turn started with the bounded wait. A
timeout there means "verify", not "failed": check `herdr agent get eng-docs` before ever
resending a prompt, because a delivered prompt that you send twice does the work twice.

Never run: `agent prompt --wait`, `agent wait` without `--timeout`, `pane wait-output` without
`--timeout`, `sleep`, or any loop that re-checks status. You must be able to answer the user
at any moment.

## Sweeping

One call lists every executor with its state:

```bash
herdr agent list | jq -r '.result.agents[] | [.name // .pane_id, .agent_status, .tab_id] | @tsv'
```

Build every jq filter out of `[...] | @tsv` or `[...] | @json`, never an interpolated `"\(.x)"`
string. The interpolated form needs double quotes inside the single-quoted shell argument, and
escaping them is a syntax error you will burn three attempts on. There is also no `.title`
field on an agent; the human-readable label lives on the pane.

`idle` and `done` both mean the executor is ready for input. `blocked` means it is sitting on
an approval or question dialog. `working` means leave it alone.

## Waking up

When you are idle, you only run when something prompts you. A finished executor must therefore
wake you, and the only mechanism for that is a prompt into your pane — `agent wait` takes a
single target, so it cannot cover several executors, and `notification show` reaches the user,
not you. The wake is addressed to the name you took at setup, and every executor gets it twice:
as the standing rule in its system prompt, and again in each brief with the concrete id and path
filled in:

```bash
herdr agent prompt orch-w2 "T3 READY_FOR_REVIEW · /abs/path/.board/T3.report.md"
```

Substitute your own name before you write the brief. Never ship the literal word
`orchestrator`: either no such agent exists and the executor gets
`{"error":{"code":"agent_not_found"}}`, or a stranger's session claimed that name and your
completion is typed into another project's pane. Your pane id works as a target too, so it is the
fallback to hand an executor that cannot find you by name — expanded to its value (`w2:p1`), never
as `$HERDR_PANE_ID`, which in the executor's shell means the executor's own pane.

The wake is a command the executor **runs**, and that is where it fails most often. An executor
that writes its report and then ends the turn with the wake line as its answer looks, in the
transcript, exactly like one that sent it — and delivers nothing. So both copies of the rule demand
the CLI's JSON result as proof, and treat the turn as unfinished until it reads `agent_prompted`.
Both also demand the wake as its own command: chained onto the report write with `&&`, a failed
wake is reported as a failed report, and the truth on disk goes unnoticed.

That line arrives as your next user message, so keep it to the task id, the status, and the
report path — you read the report yourself. The executor sends it without `--wait`. `agent_prompted`
in the result means delivered, and a second send does the work twice, so that is the end of it.
`agent_not_found` or `pane_not_found` means the target was wrong, not that you are busy: the
executor resolves you with `herdr agent list` and sends once more. If you are mid-turn the prompt
queues until your next step, and if you are sitting on an approval dialog Herdr rejects it as
`agent_blocked` — there the report on disk is still the truth and your next sweep finds it.

It types into your pane, so it can land in a line the user is composing there. That is the price
of a loop that closes by itself — mention at setup that executors will wake you. Put
`herdr notification show "<id> done" --body "<one line>" --sound done` before it when the user
also wants an audible ding.

### The wake step of every brief

End every brief with this step, after the report step of the brief template. Fill in your own
name first — the quoted heredoc expands nothing, so a placeholder reaches the executor verbatim,
and it will wake a name that does not exist.

> Then, as a separate command and as the last thing you do, **run** this — printing or
> paraphrasing it sends nothing, and I never read your answer:
> `herdr agent prompt <your-orchestrator-name> "<id> <status> · $BOARD_DIR/<id>.report.md"`
> Show its JSON result. Your turn is not finished until that result says `agent_prompted`, and one
> `agent_prompted` is enough — do not send it twice. If it says `agent_not_found`, find me in
> `herdr agent list` and send it once more. Do not discard the error with `2>/dev/null`, and do not
> chain this command to the report write with `&&`.

## Inspecting, steering, and stopping

For a stuck or drifting executor:

```bash
herdr agent get exec-docs
herdr agent read exec-docs --source recent-unwrapped --lines 120
herdr agent send-keys exec-docs esc        # dismiss a dialog
herdr agent send-keys exec-docs ctrl+c     # stop the current turn
```

A correction or a rework is a one-line prompt, sent as in *Dispatch without blocking*. Agents
on an alternate screen lose scrollback, so panes are for diagnosis only — the report file is the
channel that actually carries results.

## Closing an executor

When a stream ends, close its tab in the same turn you accept the last report:

```bash
herdr tab close w2:t3
```

A worktree workspace holds a checkout and can hold uncommitted work. Have the executor report a
clean tree, ask the user, and only then remove it: `herdr worktree remove --workspace w2`.

## Rules

- Never steal focus. `--no-focus` on every tab and worktree you create. The user stays in your
  pane.
- Split a pane only when the user asks for one, and don't resize or zoom to repair a layout you
  chose yourself.
- Close nothing you did not create: never `herdr server stop`, never the user's panes, never
  `workspace close --group` to get past `workspace_group_close_required`.
- Parse every id out of the JSON response with `jq`. Never predict or reuse a stale pane id;
  `pane move` changes it.
