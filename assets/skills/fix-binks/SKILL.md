---
name: fix-binks
description: Triage, fix, reply to, and resolve every Binks review finding on a pull request. Use only when the user explicitly invokes /fix-binks or asks to address all Binks comments.
disable-model-invocation: true
---

# Fix Binks

Process every Binks finding on the current pull request or the supplied pull request.
Treat this invocation as authorization for relevant edits, tests, commits, pushes, replies, resolutions, Binks review requests, and CI runs.
Do not merge, deploy, mark a pull request ready, override a required check, or modify unrelated work.

The optional `--rebase` argument also authorizes a rebase of the complete stack onto its freshly fetched target base.
Without `--rebase`, preserve the existing history and stack base.

## Establish the context

1. Read all repository instructions and the applicable pull request workflow skills.
2. Identify the pull request, its provider, its head commit, and its complete stack.
3. Inspect the worktree before edits.
4. Preserve all unrelated changes.
5. Stop and ask if the pull request is ambiguous or unrelated changes prevent safe publication.

For a World pull request, load `world-structure`, `world-pr-workflow`, and `gs` before any pull request action.
Use `gs` for Meteorite and `gh` for an existing GitHub pull request.
Never create a second review record for the same branch.

## Read and classify every finding

Read every Binks-authored review comment and every unresolved Binks finding.
Include outdated but unresolved threads.
Do not rely only on a summary or the required-check state.

For World, start with these commands when applicable:

```bash
devx binks finding list --provider --json
devx binks review status --json
```

Also inspect the provider conversation and inline review threads.
Use pagination when the provider API requires it.

Inspect each complete comment and its exact code context.
Verify Binks's claim independently rather than assuming it is correct.
Classify each finding as follows:

- `FIX`: The finding is valid and worth the change.
- `DECLINE`: The finding is incorrect, obsolete, redundant, or not worth the requested change.
- `NEEDS_INPUT`: The finding requires a product decision, security exception, prohibited action, or material scope expansion.

Record the stable thread identifier, comment identifier, location, verdict, evidence, and planned action.
Finish the initial classification before editing code.

## Apply valid fixes

Apply the smallest complete fix for each `FIX` finding.
Do not add unrelated refactors, abstractions, configuration, or defensive code.
Add or update a regression test when behavior changes.
Run the focused checks required by the repository after each coherent fix group.
Run the final relevant test suite before publication.

Do not edit code for a `DECLINE` finding.
Prepare a concise technical rationale with file and line evidence instead.
Stop before the affected action for any `NEEDS_INPUT` finding.

## Rebase only when requested

If `--rebase` is present, fetch the remote and rebase the complete stack onto the fresh target base.
Follow the repository's stack workflow and preserve commit boundaries.
Use `--no-gpg-sign` or `-c commit.gpgSign=false` for every commit-producing Git operation.
Use `--force-with-lease` for rewritten remote history.
Never use `--force`.
Run the relevant checks again after the rebase.

## Publish and resolve

Commit only the relevant fixes with GPG signing disabled.
Use the repository's normal publication tool to push the branch or stack.
Do not hide any remote output.

Reply to every classified Binks thread.
For `FIX`, name the change, the commit, and the verification evidence.
For `DECLINE`, state the decision and its technical justification.
Do not post vague acknowledgements.

Resolve a thread only after its reply succeeds.
For `FIX`, also require the corresponding fix on the remote branch before resolution.
Do not resolve a `NEEDS_INPUT` thread.
Do not use `devx binks finding override` as a substitute for a reply and resolution.

For Meteorite, prefer these supported commands:

```bash
gs pr comment <PR> --reply-to <COMMENT_OR_THREAD_ID> --body <TEXT>
gs pr resolve <PR> <THREAD_ID>
```

Use the current provider's supported equivalents elsewhere.
Refresh the provider state after all replies and resolutions.

## Request review and trigger CI

A push can start a Binks review automatically.
Inspect the current review state before another request.
If no current review covers the latest head, request one with the supported Binks command.

Always trigger CI for the latest remote head after the Binks work.
Trigger CI even when no source change was necessary.
In World, use `devx ci run` with the correct pull request or zone scope.
Use the repository's documented CI trigger elsewhere.
If no supported trigger is clear, stop and ask rather than guess.

Confirm that the CI request was accepted.
Inspect the initial CI state and report its run identifier or URL.
If this work caused a CI failure, fix it and repeat the publication, Binks, and CI steps.
Report unrelated or infrastructure failures without changing unrelated code.

After Binks reviews the latest head, repeat the process for new actionable findings.
Stop when every finding is resolved or requires user input.

## Report the result

Report these facts:

- The pull request URL and latest remote head.
- Each finding with its `FIX`, `DECLINE`, or `NEEDS_INPUT` verdict.
- The commits and checks for all fixes.
- The reply and resolution state for every thread.
- The latest Binks review state.
- The CI trigger and current CI state.
- Any blocker that remains.
