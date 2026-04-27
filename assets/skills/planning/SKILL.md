---
name: planning
description: Use when you have a spec or requirements for a multi-step task. Covers both writing implementation plans and executing them task-by-task with review checkpoints.
---

# Planning & Execution

## Part 1: Writing the Plan

Write comprehensive implementation plans assuming the engineer has zero codebase context and questionable taste. Document everything: which files to touch, complete code, testing, verification commands.

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

### Plan Document Header

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Architecture:** [2-3 sentences about approach]
**Tech Stack:** [Key technologies]

---
```

### Bite-Sized Task Granularity

Each step is one action (2-5 minutes):
- "Write the failing test" — step
- "Run it to confirm it fails" — step
- "Implement minimal code to pass" — step
- "Run tests to confirm pass" — step
- "Commit" — step

### Task Structure

```markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**
[Complete code]

**Step 2: Run test to verify it fails**
Run: `exact command`
Expected: FAIL with "specific message"

**Step 3: Write minimal implementation**
[Complete code]

**Step 4: Run test to verify it passes**
Run: `exact command`
Expected: PASS

**Step 5: Commit**
```

### Plan Requirements
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

---

## Part 2: Executing the Plan

### Setup

1. **Create a progress checklist from the plan:**

Record each task from the plan in working notes or status updates, grouped by phase when useful. Keep it concise and update it as work progresses.

2. **Review plan critically** — identify questions or concerns before starting

### Execution Loop

**For each task:**

1. Mark the current checklist item as in progress in your notes or status update
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Self-review (see checklist below)
5. Mark the checklist item as completed after verification passes

**After every 3 tasks, STOP and report:**
- What was implemented
- Verification output
- Any concerns
- Say: "Ready for feedback."

Wait for human response before continuing.

### Self-Review Checklist (per task)

After completing each task, before marking done:

**Spec compliance:**
- Did I implement everything requested?
- Did I build anything NOT requested? (Remove it)
- Did I interpret requirements correctly?

**Code quality:**
- Names clear and accurate?
- Code clean and maintainable?
- Following existing codebase patterns?
- No over-engineering (YAGNI)?

**Testing:**
- Tests verify behavior, not mocks?
- TDD followed (test-first)?
- Edge cases covered?

### When to Stop

**STOP executing immediately when:**
- Hit a blocker (missing dependency, unclear instruction)
- Verification fails repeatedly
- Plan has critical gaps

**Ask for clarification rather than guessing.**

### Completion

After all tasks verified:
1. Run full test suite
2. Present completed tasks and verification summary
3. Ask what the user wants next (for example: more review, PR preparation, merge, or cleanup)

## Red Flags

- Skipping verifications
- Guessing when blocked instead of asking
- Not tracking progress
- Implementing on main/master without consent
- Marking tasks done without running verification
