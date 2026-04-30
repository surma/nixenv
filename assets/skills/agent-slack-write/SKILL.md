---
name: agent-slack-write
description: Send Slack messages, replies, and reactions on the user's behalf via the write-capable build of `agent-tools slack`. Use when the user asks to post to a channel, DM someone, reply in a thread, or add/remove an emoji reaction. Pairs with the read-only `agent-tools` skill (search, message get, channel info, etc.).
compatibility: Requires `tec` on PATH (works from any cwd — no World checkout needed). Auth is shared with `devx agent-tools slack` — no separate setup.
---

# agent-slack-write

This skill grants **write access** to Slack: posting messages, replying in threads, and reacting. The read-only counterpart (search, message get, channel info, user lookup, …) lives in the `agent-tools` skill — load that one for read-side work.

## ⚠️ Mandatory safety rules

These are not optional. Slack messages are **not deletable** with this CLI — there is no `delete` or `edit` subcommand. Once a message is sent, it's permanent.

1. **Never test in real channels or real DMs.** No "test", "ping", "ignore me", "checking formatting" messages to anyone other than the user. Every test message lands in someone's notification feed.
2. **The only sanctioned test target is `#surma-river`** (id `C0AF5U16WG5`) — a channel only the user is in. Use it for any formatting check, dry-run, output-shape exploration, or "does this CLI option work" probe.
3. **Confirm the destination before every real send.** When the user asks to message a person or channel, restate the target in the response and send only after confirmation, *unless* the user has already specified the exact destination in the current request.
4. **Send once, get it right.** Do not iterate by sending → reading → resending in the real target. Iterate in `#surma-river`, then send the final version once.
5. **Never DM `Slackbot` / yourself / random user IDs you find** to "see what happens". Use `#surma-river`.

If you violate these rules you have made a real, unfixable mistake. Apologize, stop, and tell the user what was sent and to whom.

## Invocation

The write-capable binary is exposed via `tec run`. World Paths (`//…`) resolve from any cwd — you don't need to be inside a World checkout, and you don't need the zone in your sparse checkout:

```bash
tec run //areas/tools/agent-tools:slack -- <subcommand> [args...] 2>/dev/null
```

Notes:
- The bare `devx agent-tools slack` on PATH is the **read-only** build — it has no `send`, `reply`, `react`, or `unreact`. Always use `tec run //areas/tools/agent-tools:slack` for write work.
- `tec run` emits Nix evaluator progress on **stderr**. Always redirect with `2>/dev/null` (or `2>>/tmp/tec.log` if you want to keep it). Real CLI output is on stdout.
- For repeated calls in the same session, resolve the binary once with `tec build //areas/tools/agent-tools:slack 2>/dev/null` (prints a `/nix/store/.../bin/agent-slack` path) and reuse that path. Much faster than `tec run` each time.

```bash
SLACK=$(tec build //areas/tools/agent-tools:slack 2>/dev/null)/bin/agent-slack
$SLACK send surma-river "hello" --json ok,ts
```

## Auth

Shared with the read-only `devx agent-tools slack`. Verify with:

```bash
$SLACK auth status
```

Expected: `{"authenticated": true, "user": "<you>", "team": "Shopify", "tokenPrefix": "xoxc-..."}`. If it returns false, run `devx agent-tools slack auth setup` (yes, the `devx` one — auth is shared) and then come back. Don't re-auth from inside the `tec run` flow without telling the user.

## Subcommands

Only four subcommands write. Everything else (`search`, `message`, `channel`, `user`, `file`, `reactions`, `pins`, `bookmarks`, `usergroup`, `emoji`) is read-only and is covered by the `agent-tools` skill.

### send — post a top-level message

```bash
$SLACK send <channel> <text> [--json [fields]]
```

- `<channel>`: channel name (`surma-river`), channel ID (`C…`, `D…`, `G…`), or full Slack archive URL (`https://shopify.slack.com/archives/C…`).
- `<text>`: required, non-empty; empty strings fail with `Slack API error: no_text`.
- Returns `{ok, channel, ts, message}` on success. Save `ts` if you might want to thread-reply or react.

### reply — post into a thread

```bash
$SLACK reply <channel> <parent_ts> <text> [--json [fields]]
```

- `parent_ts` is the `ts` of the top-level message (e.g. `1777547262.111119`). To reply inside an existing thread, use the **root** ts, not a previous reply's ts.
- Returns `{ok, channel, ts}`.

### react / unreact — add or remove a reaction

```bash
$SLACK react   <channel> <ts> <emoji>
$SLACK unreact <channel> <ts> <emoji>
```

- `emoji` accepts both bare names (`thumbsup`) and colon-wrapped (`:tada:`). Custom workspace emoji work the same way.
- Idempotent-ish: re-reacting with the same emoji errors (`already_reacted`); unreacting an absent reaction errors (`no_reaction`).

## Channel argument resolution

The CLI accepts:
- **Channel name** for public/private channels: `surma-river`. Strip the leading `#`.
- **Channel ID**: `C…` (public), `G…` (private), `D…` (DM/IM), `M…` (mpim).
- **Slack URL**: `https://shopify.slack.com/archives/C0AF5U16WG5`.

It does **not** accept:
- Bare usernames (`surma`, `ester.kais`) — fails with `Could not resolve channel`.
- Workspace user IDs in some cases (a `U…` ID for yourself can fail; a `W…` ID for another user has worked in practice — Slack opens an IM channel implicitly).

**To DM a person, prefer:** find their existing IM channel ID via the read API, then use that. `agent-tools slack user search "Name"` returns a user id; passing that to `send` will open or reuse a DM channel and the response's `channel` field gives you the `D…` id for future use.

## Formatting (Slack mrkdwn)

Slack uses **mrkdwn**, not standard markdown. Verified behavior:

| Want | Syntax | Notes |
|---|---|---|
| Bold | `*bold*` | Single asterisks. Double asterisks render literally. |
| Italic | `_italic_` | Underscores, not asterisks. |
| Strike | `~strike~` | |
| Inline code | `` `code` `` | |
| Code block | ` ```…``` ` | Triple backticks. No language hint. |
| Blockquote | `> line` | Per-line. |
| Bullet list | `- item` | Or `• item`. No nested lists. |
| Link with label | `<https://url|label>` | Angle brackets + pipe. |
| Bare URL | `https://url` | Slack auto-linkifies and rewrites it to `<https://url>` server-side. |
| Channel mention | `<#C0AF5U16WG5>` | Use the channel ID, not the name. |
| User mention | `<@U0322KG8KFA>` | Use the user ID. |
| Newline | literal `\n` in shell-quoted strings, or use a heredoc. | |

**Markdown gotchas:** `## headings` render literally — Slack has no heading syntax; bold a line instead. `[label](url)` renders literally — use the angle-bracket form. Tables don't render — use bullets or aligned plain text.

For multi-line messages, prefer a heredoc to avoid quoting hell:

```bash
$SLACK send surma-river "$(cat <<'EOF'
*Heading-as-bold*

- bullet one
- bullet two

> a quote line

```code block```
EOF
)" --json ok,ts
```

## Output and field projection

All write subcommands support `--json [fields]` for projection. With no fields, prints the full JSON. With fields, projects to the listed keys, e.g. `--json ok,ts`. Useful for keeping the chat log clean and capturing only what you need to thread/react later.

Run any subcommand with `--json` (no fields) once to discover available keys.

## What this CLI cannot do

If the user asks for any of these, say so plainly — don't fake it:

- **No file/attachment upload.** `file` subcommand is download-only (`info`, `get`).
- **No message edit** (no `chat.update` wrapper).
- **No message delete.** Sent is sent.
- **No scheduled send.**
- **No DM open by username** — must resolve to user ID or DM channel ID first.
- **No Block Kit / interactive components.** Only mrkdwn text.

## Test recipes (use `#surma-river` only)

Standard formatting check:
```bash
$SLACK send surma-river "$(cat <<'EOF'
*bold* _italic_ ~strike~ `code`
- bullet
> quote
<https://example.com|labelled link>
EOF
)" --json ok,ts
```

Round-trip a thread:
```bash
TS=$($SLACK send surma-river "parent" --json ts --jq '.ts')
$SLACK reply surma-river "$TS" "child" --json ok
$SLACK react  surma-river "$TS" thumbsup --json ok
```

Read back what was sent (uses the read-side, fine on real channels):
```bash
$SLACK message get surma-river "$TS"
```

## Pitfalls

- **`tec run` is slow on cold caches.** First invocation in a session spends seconds in nix evaluation. Resolve the binary path once via `tec build` and reuse.
- **Stderr is loud.** Always redirect (`2>/dev/null`). Don't paste evaluator noise into chat or commit logs.
- **`reply`'s `ts` must be the thread root**, not a prior reply. If unsure, use `message get` and check the `thread_ts` field; that's the root.
- **Ampersands and angle brackets in user text get HTML-escaped on the wire** (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`). Slack renders them correctly; don't double-escape.
- **No idempotency.** Re-running `send` posts the message again. If a previous run looked like it failed, check Slack first before retrying.
- **The `surma-river` rule is absolute** — even for "I just want to see what the JSON looks like." That's what `--json` (with no value) is for: it prints the available fields without sending. Use that *first* whenever you can.
