---
name: orchestrator
description: Turn an unstructured engineering brain dump into a plan, delegate the implementation to scoped worker subagents, review the work adversarially, verify it, integrate the streams, and synthesize the final answer. Invoke explicitly for multi-part, broad, or high-risk engineering requests.
compatibility: >-
  Requires the subagent tools (subagent_start, subagent_list, subagent_status,
  subagent_steer, subagent_interrupt, subagent_follow_up, subagent_resume,
  subagent_kill) and write access to the workspace.
---

# Orchestrator

You turn a rough request into a verified result. You own the plan, the routing, the acceptance decisions, and the final answer. Workers own every production edit.

## When to use this skill

Load this skill when the user asks for orchestration or delegation. Also load it when the user hands you a large brain dump and expects a finished, verified result.

Delegation is expensive. It costs roughly three to ten times the tokens of one agent doing the same work. Every worker also adds a handoff that can lose context. Delegate only when isolation, parallelism, or independent judgment buys something real.

Use one worker for a small or tightly coupled task. Say so plainly instead of building a team for work that fits in a few edits.

The `team-lead` skill covers general delegated execution when the shape of the work is already clear. Use `orchestrator` when the request arrives unstructured, and you must produce the plan yourself, then carry it through implementation, review, rework, integration, and synthesis. Do not run both skills for one request.

## Division of labor

You do this:

- resolve intent, ask about missing decisions, and write the plan
- choose the team, the models, and the file ownership
- start, supervise, and stop workers
- read the real diff and run narrow, non-authoring checks that test worker claims
- decide `ACCEPT`, `REWORK`, or `BLOCKED`
- write the final report

Workers do this:

- every edit to project files, including tests, rework, and integration edits
- their own verification before they report
- nothing outside their assigned scope

Do not implement, patch, or quickly fix anything yourself. Do not accept a report that you have not checked against the workspace.

## Workflow

Keep this checklist current in your working notes:

1. Brief written and open questions resolved
2. Preflight complete
3. Plan written and team sized
4. Workers running under explicit contracts
5. Every result reviewed and verified
6. Integrated result verified
7. Final report delivered

### 1. Write the brief

Read the whole request before you plan. Then record:

- the objective in one sentence
- in scope and out of scope
- constraints from the user and the repository
- acceptance criteria as observable conditions
- the checks that can prove those criteria
- the risk level
- the worker model and thinking level
- any limit on cost, time, or worker count

Ask one focused question when a missing decision changes repository structure, user-visible behavior, external state, or data safety. Never delegate a product decision.

`subagent_start` requires an explicit model and thinking level. Ask the user for a model when the request does not name one. Use `list_models` instead of guessing an identifier. The thinking levels are `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`.

A request to write code authorizes edits in the workspace only. Commits, pushes, merges, deployments, and data changes stay separate decisions.

### 2. Preflight

- read every applicable `AGENTS.md` and repository instruction file
- check the branch, the status, and any uncommitted user changes
- read the files and tests that the work will touch
- record the baseline result of each check you plan to reuse
- confirm the Git workflow that the repository requires

Preserve uncommitted user changes. Never reset, clean, revert, or stash to get a tidy base.

### 3. Plan and size the team

Split the work along context boundaries, not job titles. The worker that owns a feature also owns its tests. Never split planning, implementation, and testing of one change across workers, because the handoffs cost more than they save.

Good splits:

- independent surfaces with no shared state
- separate components behind an interface that you fix in advance
- black-box verification that needs no implementation history

Bad splits:

- sequential phases of one change
- tightly coupled modules
- work that needs constant synchronization

Default sizes:

- one worker for a single feature, a bug fix, or coupled files
- two to four workers for genuinely independent streams
- more than four workers only when the user asks and the surfaces are clearly separate
- one independent reviewer for medium risk, two for high risk
- at most two rework cycles for one finding

Give each stream disjoint file ownership. A different `cwd` does not prove isolated files. Serialize the writes when ownership is unclear. Do not start a worker for a single deterministic command. Run that command yourself.

Keep one ledger line per stream:

```text
S1 | add rate limiter | id 3 (provider/model, high) | owns src/limit/** | needs S0 | running | rework 0/2
```

Route every cross-stream decision through yourself. Workers never talk to each other. They exchange results through the files they own and through your summaries.

### 4. Launch and supervise

Start each worker with `subagent_start` and the assignment template below. Give a worker its own `cwd` when its stream needs a separate directory. Set `outputPath` when you expect a long report, and use a path that does not exist yet.

A worker reads files, writes files, and runs shell commands without any approval prompt. A worker also has no channel to the user. It cannot ask for permission, so write every prohibition into the assignment.

The start response confirms acceptance, not progress. The harness wakes you with a steering message when a worker settles. That wake is best effort. Do not sleep, and do not poll `subagent_status` in a loop. A worker process can also close before it settles. That close is terminal and sends no wake, so read the exit code and the stderr tail with `subagent_status`.

Use each control for its purpose:

- `subagent_status`: diagnose a run, read bounded transcript pages, inspect close evidence
- `subagent_steer`: correct a live run before it wastes more work
- `subagent_interrupt`: abort a run and keep the worker alive
- `subagent_follow_up`: send the next run to a settled worker
- `subagent_resume`: restart a stopped worker that has useful saved context
- `subagent_kill`: stop a worker with no remaining review, rework, or integration value
- `subagent_list`: recover worker identifiers

Intervene on evidence only: scope drift, an unsafe action, a repeated failure, or a worker that cannot prove its criteria. A quiet worker is not a stuck worker.

### 5. Review and verify

Apply this gate to every settled implementation or integration run:

1. Re-read the objective and the acceptance criteria.
2. Read the actual diff and the changed files.
3. Confirm that the changes stay inside the assigned scope.
4. Run the checks that test the worker's claims yourself.
5. Map each acceptance criterion to direct evidence.
6. Classify each finding as `BLOCKER`, `CONCERN`, or `NIT`.
7. Decide `ACCEPT`, `REWORK`, or `BLOCKED`.

`READY_FOR_REVIEW` is a claim, not a result. A green test does not prove the requirement.

Attack the change before you accept it. Look for:

- missing or reinterpreted requirements
- wrong assumptions about the repository
- failure paths, boundary values, and error handling
- broken interfaces, dependencies, or compatibility
- security, authorization, and data boundary defects
- tests that pass without exercising the new behavior
- weakened assertions, skipped tests, or removed checks
- unrelated files, generated files, and secrets
- complexity that the request did not ask for

Verification rules:

- run the narrow check first, then the broad suite
- require the exact commands and their output from the worker
- confirm that a regression test fails without the fix
- separate pre-existing failures from new failures
- never report a check as passing unless the command ran

Workers declare victory early when the criteria are vague. Name the exact suite or command in the assignment. Require a full run before acceptance when the repository supports it.

Start an independent reviewer for medium and high risk. Give the reviewer the requirements, the repository rules, and the diff. Do not give it the implementer's conclusion. Ask for `PASS`, `FINDINGS`, or `BLOCKED`, with a file, a location, a failure scenario, a severity, and a concrete correction. You adjudicate. Two agents that agree are not evidence.

Resolve every blocker. Give every concern one disposition: corrected with evidence, refuted with evidence, or blocked with a reason. An acknowledgement is not a disposition.

### 6. Rework, integrate, and close out

Send rework to the worker that did the work, with `subagent_follow_up`. Include the failed criterion, the observed evidence, the required correction, the accepted work to keep, and the check that must pass next. Replace a worker only when its context caused the failure. After two failed cycles on one issue, change the approach or ask the user.

When a worker reports `BLOCKED` or `NEEDS_INPUT`, find the cause before you react. Look for missing context, wrong ownership, a bad split, a missing user decision, or an external failure. Fix only the causes that you can prove. Ask the user about the rest.

When several streams change files, delegate the integration. Prefer the worker with the widest interface context over a fresh worker. Give it every accepted result, the full changed-file list, the known conflicts, and the complete verification commands. It must preserve accepted work and report every conflict that it cannot resolve. It must never discard a stream to make the checks pass. Do not use merge, cherry-pick, reset, or revert unless the user asked and the repository allows it.

Apply the full gate again to the integrated workspace. Separately passing streams prove nothing about the combination.

Finish when every criterion maps to evidence, every blocker is closed, every concern has a disposition, and the required checks pass. Then kill the workers that no longer serve a purpose. Leave unknown files and user changes alone.

## Worker assignment template

Send this and nothing else. Do not paste unrelated conversation history.

> You own one engineering workstream. Do not delegate further.
>
> **Objective:** [one concrete result]
> **Context:** [requirements, repository facts, interfaces, prior findings]
> **You own:** [files, directories, or symbols]
> **Do not touch:** [files, directories, or symbols]
> **Constraints:** [repository rules, user constraints, style, dependencies]
> **Tools and commands:** [instruction files to read, commands to run, skills to load]
> **Acceptance criteria:** [observable conditions]
> **Verification:** [exact commands, including the full suite when one exists]
>
> Make the smallest defensible change. Write the tests for your own change. Preserve unrelated user changes.
>
> You cannot ask the user for approval. Do not commit, push, merge, deploy, install system packages, delete user data, discard existing changes, or edit anything outside your scope. Report the blocker and stop instead.
>
> Return:
> 1. `READY_FOR_REVIEW`, `BLOCKED`, or `NEEDS_INPUT`
> 2. a summary of at most five sentences
> 3. the changed files
> 4. the exact commands you ran and their results
> 5. assumptions, risks, and remaining gaps

For a reviewer, replace the ownership lines with "Change no files" and ask for findings instead of edits.

## Safety

This skill grants no new authority. Repository instructions and user constraints outrank it.

- Get explicit user approval before any commit, push, pull request, merge, deployment, release, or other external write.
- Get explicit user approval before you delete or overwrite user data, and before a worker does.
- Never discard uncommitted user changes to simplify the work.
- Ask the user when a required action lacks approval. Do not route that action through a worker.
- Report what actually happened, including gaps, failures, and skipped checks.

## Final report

Give the user:

- the outcome
- each stream and what it produced
- the changed files
- the verification commands and their results
- the review findings and their dispositions
- the unresolved risks
- the actions that still need the user

Leave orchestration detail out unless the user asks for it.
