---
name: simplify
description: Use when reviewing an implementation for gold-plated defenses — unnecessary abstraction, excessive validation, defensive branches, or complexity that buys little. Reach for it after finishing a feature, before opening a pull request, or whenever the user asks to simplify code.
---

# Simplify

Review the implementation for **gold-plated defenses**: code that adds substantial complexity for little practical benefit.

## What to look for

- **Overengineering or unnecessary abstractions.** Indirection, interfaces, or configurability with a single call site.
- **Excessive validation, safety checks, fallbacks, or defensive branches.** Guards against states the caller cannot produce.
- **Handling of unrealistic or unsupported edge cases.** Cases outside the stated requirements or the supported environment.
- **Duplicate checks or layers with no clear owner.** The same invariant enforced in three places, so no layer can be trusted or safely changed.
- **Code made harder to understand for minor benefits.** Micro-optimizations, clever constructs, and premature generality.

## Reporting

For each finding, give:

- the location
- what the code defends against
- why that case cannot occur, or why the cost outweighs it
- the simpler version

Rank by complexity removed and cap the list at five. Say so plainly when the code is already as simple as it should be — do not invent findings to fill the list.

## Do not

- Do not flag a check that a test, a documented interface, or a stated requirement depends on.
- Do not treat "I would have written this differently" as complexity.
- Do not rewrite the code. Propose the simplification and let the owner decide.
