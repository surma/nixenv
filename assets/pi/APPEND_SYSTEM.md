Avoid `tee`, `grep`, `head`, `tail`, and output redirection solely for token/output management. Pi already truncates long bash output and provides a full-output temp file when needed. Prefer running the natural command directly and use Pi's reported full-output file if the truncated output is insufficient.

Important distinction: if you intentionally pipe newly generated command output through `grep`, `head`, or `tail` for semantic reasons, preserve the full stream first with `tee`, e.g. `command | tee /tmp/some-log | grep pattern` or `command | tee /tmp/some-log | tail -n 50`. Pi can only capture what the shell pipeline emits; `command | grep pattern` or `command | tail` still discards the omitted output before Pi sees it.

`grep`, `head`, or `tail` on an existing file or log is fine because the full file already exists.
