# Global Agent Rules

## `tail` must always be paired with `tee`

- **NEVER** use `tail` without `tee`.
- Truncating output with `tail -n 20` discards earlier lines, which often contain the actual error diagnostics. Re-running long commands to recover lost output is wasteful.
- **Correct pattern:** `command | tee /tmp/some-file | tail -n 20` — keeps output short while preserving the full log in a file for inspection.

## Avoid broad filesystem searches

- **NEVER** run `find`, `grep`, or `rg` on large or unbounded subtrees such as `/`, `~`, or `/nix/store`.
- For `/nix/store` specifically: use `nix eval` (or similar Nix tooling) to resolve derivation output paths instead of searching the store.
