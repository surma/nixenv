---
name: triple-helix
description: Use whenever working on a project where intent, tests, and implementation should evolve together — i.e. nearly any non-trivial change. Always applies when an `intent/` directory or `INTENT.md` file is present, when an AGENTS.md cites the triple helix, or when the user invokes triple-helix discipline. Covers both bootstrapping new projects and working on existing ones.
---

# Triple Helix

## The Idea

Three artifacts describe a system: **intent**, **tests**, **implementation**. Each is a projection of the same underlying behavior. Any two reliably reconstruct the third; any one alone does not.

- **Intent** — a written, precise description of desired behavior. Not a design doc that rots; a living specification specific enough to derive tests and code from.
- **Tests** — executable verification. Samples behavior; demonstrates contracts hold.
- **Implementation** — the running code.

When the spec and the code disagree, one of them drifted. The whole point of three strands is to make drift detectable instead of silent. Two strands can verify each other; when they conflict there is no tiebreaker. The third strand is the tiebreaker.

## When This Applies

Load and apply this skill when **any** of the following is true:

- The project has an `intent/` directory or an `INTENT.md` file at its root.
- The project's `AGENTS.md` (or equivalent) cites the triple helix.
- The user explicitly invokes triple-helix discipline ("apply the triple helix", "let's do this triple-helix style", etc.).

If none are true, do not unilaterally introduce the discipline. Bootstrapping is a real cost and a structural decision. Ask first.

---

## The Four Working Rules

1. **Every behavioural change touches all three strands.** New flag, error code, state transition, wire field, CLI option, config key — update the intent doc that names it, add or update a test that covers it, change the implementation. Diff size is irrelevant: a one-line behavioural change can break an invariant the spec encodes.

2. **Read the intent doc nearest your change before writing code.** It documents invariants the running code already relies on. Skip it and you will re-derive constraints the spec already states — usually wrong. Read the *whole* nearest doc, not just keyword-matched paragraphs.

3. **Integrate, don't append.** If the intent doc has a state-machine table, add your new state to the table. If it has an error-code map, add your new error there. Appending a new "section about my change" at the bottom is how specs rot into design-doc graveyards. Match the spec's existing level of detail.

4. **Distinguish snapshot from log.** The intent doc is the *current contract*, not the change history. Don't append "Completed: X" sections. Narrative belongs in commit messages, PR descriptions, or a separate volatile `docs/` directory (changelogs, runbooks, progress trackers). Intent is what the system *is*; logs are how it got there.

---

## Working on an Existing Triple-Helix Project

### Before any change

1. Locate the intent doc nearest your change. Read it completely.
2. Locate the existing tests for the area. Note their level of detail and shape.
3. **Only then** read the implementation.

If the spec and the code disagree, **stop**. Surface the discrepancy to the user. Don't silently pick the convenient one — figure out which strand drifted, then decide together which to fix.

### Making the change

For each change, all three boxes must be ticked before commit:

- [ ] **Intent** updated (integrated into the existing structure, not appended).
- [ ] **Test** added or updated (covers the new behavior, not just the happy path).
- [ ] **Implementation** matches both.

If you find yourself wanting to skip the intent update because "it's just a small fix," re-read rule 1.

### Self-review before commit

- Does the intent doc, read alone, describe the new behavior accurately and at the same level of detail as its surroundings?
- Does the test, run against the *old* code, fail? (If not, it's not testing your change.)
- Does the implementation contain anything not motivated by the spec?

If any answer is no, you are not done.

---

## Bootstrapping a New Project

Bootstrap is intent-first. Don't write code until there is at least a paragraph of intent. When bootstrapping with the user, ask one question at a time — what the system is for, who uses it, what invariants must hold — and write the answers down as you go.

### Sizing the layout

Pick the smallest shape that fits. You can always grow later.

| Project size | Intent | Tests | Implementation |
|---|---|---|---|
| **Small** (single binary, one concern) | `INTENT.md` at repo root | `*_test.*` colocated with source | flat source layout |
| **Medium** (a few components) | `intent/<component>.md` per component, plus `intent/README.md` as index | colocated unit tests + a small e2e dir | source root with subdirs |
| **Large** (many components / services) | `intent/` directory, `intent/README.md` index, `intent/AGENTS.md` working agreement | colocated + dedicated e2e zone | per-component source trees |

Rules of thumb:

- An intent file should fit on roughly one screen of reading. If one is past ~500 lines, split it.
- One canonical home per concept. If two intent files describe overlapping behavior, merge them or refactor the boundary.

### Volatile companion docs

Keep a `docs/` directory (or equivalent) deliberately separate from `intent/`. The split matters:

- `intent/` is **normative and slow-moving**: the contract about what the system is.
- `docs/` is **volatile**: changelogs, runbooks, progress trackers, deploy logs, design-decision records. Snapshots of *now*, not contracts about *what*.

When in doubt: if the document would still be true a year from now after the system evolves, it's intent. If it'll be stale by next quarter, it's a doc.

### Bootstrap checklist

1. Write `INTENT.md` (or the first `intent/` doc): what the system is, what it isn't, who it's for, the invariants it must hold, the failure modes that are out of scope.
2. Write the smallest test that exercises the core invariant. Run it. Watch it fail.
3. Implement the minimum that makes the test pass.
4. If the project will grow, add an `AGENTS.md` that links to this skill and restates the four rules.
5. Add a `docs/` directory only when there's volatile material to put in it. Most small projects don't need one yet.
6. Commit. The first commit should already be triple-helix-shaped: intent, test, implementation, all in one place.

### When intent lives outside the repo

The intent strand can live outside the repo (a knowledge base, a wiki, a separate doc store) when the user explicitly directs it. The discipline is unchanged; only the storage moves. Two constraints when doing this:

- **One canonical home.** The intent lives *either* in the repo *or* in the external store — not both. The other side carries a pointer, nothing more.
- **Bidirectional links.** Each side links to the other. Otherwise one side becomes invisible to its readers.

Do not move intent out of the repo on your own initiative. The default is in-repo.

### What counts as "tests"

The test strand is "executable verification" in the broadest sense. For most projects that's `*_test.*` files. For configuration, infrastructure, or content projects it might be:

- `nix flake check`, `terraform validate`, schema validators
- snapshot tests, golden-file tests
- example workloads that must succeed
- assertions baked into a build pipeline

The form is negotiable. The property is non-negotiable: it must be **executable**, **automatic**, and **fail loudly when the implementation drifts from the intent**.

---

## Red Flags

Stop and reconsider if you see any of these:

- "I'll update the spec later." → No. Update it in the same commit, or don't ship.
- A new section appended to `intent/foo.md` titled "Implementation notes for change X." → Integrate into the existing structure, or delete.
- A test that passes only because the implementation is wrong in a way the spec doesn't address. → The spec is incomplete. Fix the spec first.
- An intent doc that reads like a marketing pitch ("flexible, performant, scalable"). → Rewrite as invariants and behaviors, not adjectives.
- Four or more "spec-like" artifacts (design doc, RFC, spec, schema, ADR). → Fold them. Two-of-three is the constraint; more strands dilute it.
- Intent that describes *how* instead of *what*. → That's implementation prose in the wrong file. Move it.

---

## Quick Reference

| Strand | Question it answers |
|---|---|
| Intent | What should this do, and under what conditions? |
| Tests | Does it actually do that? |
| Implementation | How does it do it? |

| Drift kind | How you'll see it | Fix |
|---|---|---|
| Spec ahead of code | Test written from spec fails on current code | Implement the missing behavior, or revise the spec |
| Code ahead of spec | Behavior visible in code with no spec entry | Update the spec to describe it (or remove the code) |
| Tests ahead of either | Test references behavior neither spec nor code shows | Decide which is canonical, then align the other two |

| Rule | One-line summary |
|---|---|
| 1 | Touch all three strands per behavioural change. |
| 2 | Read nearest intent doc before coding. |
| 3 | Integrate into existing structure, don't append. |
| 4 | Snapshot ≠ log. Keep narrative out of intent. |
