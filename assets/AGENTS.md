# Global Agent Rules

## `tail` must always be paired with `tee`

- **NEVER** use `tail` without `tee`.
- Truncating output with `tail -n 20` discards earlier lines, which often contain the actual error diagnostics. Re-running long commands to recover lost output is wasteful.
- **Correct pattern:** `command | tee /tmp/some-file | tail -n 20` — keeps output short while preserving the full log in a file for inspection.

## Avoid broad filesystem searches

- **NEVER** run `find`, `grep`, or `rg` on large or unbounded subtrees such as `/`, `~`, or `/nix/store`.
- For `/nix/store` specifically: use `nix eval` (or similar Nix tooling) to resolve derivation output paths instead of searching the store.

## Git commits must disable GPG signing

- When creating a commit, always pass `--no-gpg-sign`.
- Without `--no-gpg-sign`, the commit may hang indefinitely waiting for GPG interaction.

# Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- Do not silently choose among multiple plausible project-level conventions (file layout, CI/provider setup, config location, package manager, deployment shape, naming scheme, etc.). If the correct choice is not clearly evidenced by the repo or the user request, stop and ask.
- The less reversible a decision is, the less acceptable it is to make on assumption. Be especially cautious with changes that create persistent structure, alter workflow/tooling, or change semantics.

Quick decision check before making a nontrivial change:
- Are there multiple plausible choices?
- Would different choices affect repo structure, workflow, tooling, or user-visible behavior?
- Can I verify the right choice from the repo, docs, or user request?
- If not, have I stopped and asked instead of guessing?

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.gg
