---
name: commitsit
description: Commit and push the current conversation's changes, open or update a PR, then iterate against CI and the Binks review bot until CI is green and Binks is satisfied. Use when the user says "/commitsit" or asks to "ship it", "commit and babysit", "push and watch CI", or otherwise wants the agent to drive a change all the way through review.
---

# /commitsit

Drive the current conversation's work to a green, reviewed PR with as little hand-holding as possible. The user has already decided the change is ready — your job is to commit, push, open or update the PR, then iterate against CI and Binks until both are satisfied.

## Phase 1 — Commit & push

1. **Inspect state.** Run `git status`, `git diff`, and `git log -n 5 --oneline` in parallel. Read the current branch name.
2. **Identify in-scope changes.** Stage only files that pertain to the current conversation's work. If you see unrelated dirty files, ask the user before staging them. Never `git add -A` without thinking.
3. **Commit.**
   - If the repo has a project-specific commit-message skill (e.g. `create-shell-commit-message`), invoke it.
   - Otherwise write a concise message describing the *why* of the change.
   - If there are no staged changes but the branch is ahead of `origin`, skip straight to the push.
4. **Push to origin.**
   - Prefer the project's branch tooling if one is in use (e.g. `gt submit` for Graphite — check for `.graphite_*` config or existing `gt` usage in the repo).
   - Otherwise `git push -u origin HEAD`.
   - If this is a force-push to an existing branch (commit-amended or rebased), use `git push --force-with-lease`, never `--force`. Never force-push `main`/`master`.
5. **Open or update the PR.**
   - `gh pr view --json number,url,state` to check if a PR already exists for the branch.
   - If not, `gh pr create` (use the project's PR-creation skill if one exists, e.g. `create-shell-pull-request`).

6. **Explicitly trigger CI on every push.** Pushes alone don't always start the required checks — trigger CI yourself after each push (initial or follow-up).
   - **In World worktrees (anything under `~/world`): always run `devx ci run` after every push.** Don't skip this even on the first push of a new branch, and don't assume CI auto-started — it often hasn't, or has only started a subset of stages. If you need to scope to a specific zone or stage, pass `-z <zone>` / `-s <stage>`.
   - Outside World: use the project's equivalent (`bk build create` for Buildkite, `gh pr comment <n> --body "/retest"` or `gh run rerun` for GitHub Actions). If unsure, ask once and remember.
   - Use `devx ci status` (or the project equivalent) only to *check* state, never to trigger it.

State explicitly to the user: branch name, PR URL, and what you triggered.

## Phase 2 — Watch CI and Binks

Now iterate until **both** CI is green **and** Binks has no outstanding actionable comments.

### Watching CI

Use a `Monitor` invocation with a poll loop that emits one line per terminal status change. Filter must cover success *and* failure signatures — silence is not success.

Example shape (adapt the status command to the project's CI tool):

```bash
prev=""
while true; do
  s=$(devx ci status --pr <N> --json 2>/dev/null || gh pr checks <N> --json name,bucket,state)
  cur=$(jq -r '.[] | select(.bucket!="pending" and .state!="PENDING" and .state!="IN_PROGRESS") | "\(.name): \(.bucket // .state)"' <<<"$s" | sort)
  comm -13 <(echo "$prev") <(echo "$cur")
  prev=$cur
  jq -e 'all((.bucket // .state) | IN("pending","PENDING","IN_PROGRESS") | not)' <<<"$s" >/dev/null && break
  sleep 60
done
```

Poll interval: ~60s for remote CI APIs. Use `persistent: true` for long runs.

### Watching Binks

Binks is Shopify's automated code review bot. It posts review comments on the PR.

- Fetch comments after each push: `gh api repos/<owner>/<repo>/pulls/<n>/comments` and `gh pr view <n> --json reviews,comments`.
- Filter for the Binks bot author (login typically contains `binks`; verify against the repo's actual bot account).
- Re-fetch when the PR head SHA changes (Binks re-reviews on push).
- Don't quote raw comment bodies back to the user — summarize.

### Fixing what comes back

For each iteration:

1. Collect failures: failing CI jobs (read the job logs — `gh run view --log-failed`, `bk build view`, etc.) and new Binks comments.
2. Decide per item: **fix it**, **defer it**, or **flag it as questionable** (see Phase 3).
3. Make the fixes locally.
4. Commit:
   - If the new commits are small fixups for the same logical change and the PR isn't yet under formal human review, prefer `git commit --amend` (or `git commit --fixup` + `gt modify` for Graphite stacks) and force-push with `--force-with-lease`.
   - If the PR has already received human review approvals or substantive comments, prefer additive commits so reviewers can see what changed — don't rewrite history out from under a reviewer.
5. Push, then **explicitly trigger CI** (same as Phase 1 step 6 — `devx ci run` in World, project equivalent elsewhere). Do this on every push, not just when checks look stuck.
6. Loop.

Do not amend or force-push `main`/`master`. Do not skip hooks (`--no-verify`) or signing.

## Phase 3 — Binks comments you shouldn't silently address

Some Binks comments are wrong, ambiguous, or not worth the churn. **Do not address these blindly.** Instead, when you finish (CI green and remaining Binks comments are only these flagged ones), surface them to the user in your final response:

- Quote the file/line and a one-sentence summary of what Binks said.
- State why you're flagging it (e.g. "this looks like a false positive — the value is already validated upstream at X:Y", or "unclear whether Binks wants A or B").
- Propose what you'd do, and ask the user to confirm.

Categories that typically warrant flagging rather than silent fixing:

- Style/nit comments that conflict with the existing local convention in the file.
- Suggestions that would expand scope beyond the conversation's task.
- Comments that appear to misread the code (false positives).
- Comments where the requested change has non-obvious tradeoffs (perf, API surface, public types).
- Anything that would require schema migrations, dependency bumps, or touching files the user didn't ask about.

Always-fix categories (don't flag, just do):

- Obvious bugs Binks caught (null derefs, off-by-one, missing await, wrong arg order).
- Lint/format violations.
- Test failures.
- Type errors.
- Security issues (injection, missing auth checks, leaked secrets).

## Stopping conditions

You're done when **all** of the following hold:

1. CI is fully green on the latest pushed commit.
2. Binks has either approved or its only remaining comments are ones you've flagged in your final user response.
3. You've reported the final PR URL, the head commit SHA, and the list of flagged Binks comments (if any).

Stop and ask the user if:

- The same CI check has failed three iterations in a row in the same way — you're probably missing context.
- A fix would require destructive operations (force-push to `main`, schema migrations, secret rotation, dependency removal).
- Binks asks for something that touches files outside the conversation's scope.
- You're about to spend more than ~30 minutes of wall time on a single failure.

## Tools and conventions

- Prefer the project's existing tooling when present. Check for and use:
  - `gt` (Graphite) for branch/PR operations on stacked PRs.
  - `devx ci status` in World for CI status.
  - Project-specific `create-*-pull-request` and `create-*-commit-message` skills.
  - `dev check` / `fastcheck` for local pre-push validation.
- Run pre-push validation locally before each push when the project provides a fast checker — catching a lint error locally is one round-trip cheaper than catching it in CI.
- Respect repo-level rules in `CLAUDE.md` (no `[skip ci]`, no agent-authored DB migrations, no git config edits, etc.).
- Parallelize independent reads (status, log, PR check, Binks comments) — they don't depend on each other.

## What success looks like in your final message

A short report:

- ✅ PR `<url>` — head `<sha>`
- ✅ CI green (N checks)
- ✅ Binks: approved / no outstanding comments
- ⚠️ Flagged Binks comments needing your call: (list, or "none")
- Iterations: N pushes, M Binks rounds

Keep it tight. The user can read the PR if they want detail.
