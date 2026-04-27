---
name: debugging
description: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes.
---

# Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

## The Four Phases

Complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully** — Don't skip past them. Read stack traces completely. Note line numbers, file paths, error codes.

2. **Reproduce consistently** — Can you trigger it reliably? What are the exact steps? If not reproducible → gather more data, don't guess.

3. **Check recent changes** — Git diff, recent commits, new dependencies, config changes, environmental differences.

4. **Gather evidence in multi-component systems** — Add diagnostic logging at each component boundary. Run once to see WHERE it breaks. Then investigate that specific component.

5. **Trace data flow** — Where does the bad value originate? What called this with bad input? Keep tracing up until you find the source. Fix at source, not at symptom.

### Phase 2: Pattern Analysis

1. **Find working examples** — Locate similar working code in the same codebase
2. **Compare against references** — Read reference implementation COMPLETELY. Don't skim.
3. **Identify differences** — What's different between working and broken? List every difference.
4. **Understand dependencies** — What settings, config, environment does this need?

### Phase 3: Hypothesis and Testing

1. **Form single hypothesis** — State clearly: "I think X is the root cause because Y"
2. **Test minimally** — Smallest possible change to test hypothesis. One variable at a time.
3. **Verify** — Did it work? Yes → Phase 4. No → NEW hypothesis. DON'T add more fixes on top.
4. **If you don't know** — Say "I don't understand X." Don't pretend.

### Phase 4: Implementation

1. **Create failing test case** — When feasible, capture the bug with the simplest reproduction before changing implementation code.
2. **Implement single fix** — Address root cause. ONE change. No "while I'm here" improvements.
3. **Verify fix** — Test passes? No other tests broken? Issue resolved?
4. **If fix doesn't work** — Count attempts. If < 3: return to Phase 1. **If ≥ 3: STOP and question the architecture.** Discuss with human before more attempts.

## Track Progress

Maintain a simple phase checklist while debugging:

- Phase 1: Root cause investigation
- Phase 2: Pattern analysis
- Phase 3: Form and test hypothesis
- Phase 4: Implement and verify fix

Update the checklist as phases move from pending to in progress to complete, and report it when useful.

## Red Flags — STOP and Return to Phase 1

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "Add multiple changes, run tests"
- "I don't fully understand but this might work"
- Proposing solutions before tracing data flow
- "One more fix attempt" (when already tried 2+)
- Each fix reveals new problem in different place

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple" | Simple issues have root causes too. |
| "Emergency, no time" | Systematic is FASTER than guess-and-check. |
| "Just try this first" | First fix sets the pattern. Do it right. |
| "I see the problem" | Seeing symptoms ≠ understanding root cause. |
| "One more fix" (after 2+) | 3+ failures = architectural problem. |

## Quick Reference

| Phase | Key Activities | Done When |
|-------|---------------|-----------|
| 1. Root Cause | Read errors, reproduce, check changes, trace data | Understand WHAT and WHY |
| 2. Pattern | Find working examples, compare | Identified differences |
| 3. Hypothesis | Form theory, test minimally | Confirmed or new hypothesis |
| 4. Implementation | Create test, fix, verify | Bug resolved, tests pass |
