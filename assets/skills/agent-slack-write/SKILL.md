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
6. **A non-zero exit from `send` / `reply` does NOT mean the message wasn't sent.** The CLI executes the side-effecting Slack API call *before* it validates flags like `--json <fields>`. A successful send followed by a bad field projection (e.g. `--json permalink` — there is no `permalink` field) exits 1 with a stderr error, but the message is already in Slack. **If a write subcommand exits non-zero, your next action is to read the channel — not retry.** See §"Recovery when a send looks failed" below for the exact steps. Retrying without checking is how you produce duplicate messages, and that's an unfixable mistake.

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

**Field validation happens AFTER the side-effecting API call.** A bad field name (`--json permalink` when only `ok, channel, ts, message` are available) exits non-zero with `Unknown field(s): … / Available: …` *and the message has already been posted*. This bit hard once already and produced a duplicate.

Rules of thumb that make this trap unreachable:

- **Never invent field names.** The available fields for `send`/`reply` are exactly `ok, channel, ts, message`. Nothing else. (Notably: there is no `permalink` — construct one yourself from `channel` + `ts` if you need it: `https://shopify.slack.com/archives/<channel>/p<ts-with-dot-stripped>`.)
- **If you don't actually need projection, omit `--json` entirely** on real sends. The default human-readable output is fine and removes the trap surface.
- **Discover field names BEFORE the real send**, not on it: run `--json` (no field list) once against `#surma-river` to see the full shape. Then on the real send, project only fields you've personally seen in that output.

The sanctioned `--json` projection for a real `send`/`reply` you might thread/react against later is `--json ok,ts` (or `--json ts --jq '.ts'` if you only want the bare timestamp). Anything beyond `ok, channel, ts, message` is invented and will trip the post-send error.

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

## Recovery when a send looks failed

If `send` or `reply` exits non-zero, **stop**. Do not retry. The most common reason for a non-zero exit is a post-send error (e.g. `--json` field name typo, jq filter failure) where the message *did* go through. Steps:

1. Read the destination channel's most recent messages and look for your text:
   ```bash
   devx agent-tools slack message list <channel> --limit 5 --json ts,user,text
   ```
   (Use the read-only CLI here — it's safe and fast.)
2. If your message is present: the send succeeded. Tell the user, do not retry. If you needed the `ts` for a follow-up reply/react, take it from the listing.
3. If your message is genuinely absent: now you can retry. Inspect the original stderr to figure out what actually broke (auth? channel resolution? rate limit?) and fix that before re-running.
4. If you discover you produced a duplicate (you retried before checking, or two sends genuinely landed): tell the user immediately, name both timestamps, and offer to delete one via `chat.delete` (see §"Escape hatch: direct Slack API"). The CLI cannot delete; the API can. Deleting one of your own duplicates is the legitimate use case for `chat.delete`.

## Pitfalls

- **`tec run` is slow on cold caches.** First invocation in a session spends seconds in nix evaluation. Resolve the binary path once via `tec build` and reuse.
- **Stderr is loud.** Always redirect (`2>/dev/null`). Don't paste evaluator noise into chat or commit logs.
- **`reply`'s `ts` must be the thread root**, not a prior reply. If unsure, use `message get` and check the `thread_ts` field; that's the root.
- **Ampersands and angle brackets in user text get HTML-escaped on the wire** (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`). Slack renders them correctly; don't double-escape.
- **No idempotency.** Re-running `send` posts the message again. If a previous run looked like it failed, **read the channel first** — see §"Recovery when a send looks failed". A non-zero exit from `send`/`reply` is overwhelmingly likely to be a post-send projection error, not a real send failure.
- **The `surma-river` rule is absolute** — even for "I just want to see what the JSON looks like." That's what `--json` (with no value) is for: it prints the available fields without sending. Use that *first* whenever you can.
- **`message get` silently strips `files`, `attachments`, and `blocks`.** Even with `--json` and no projection, the listed available fields are only `ts, channel, user, text, threadTs, replyCount, reactions, permalink`. There is no flag to expose attachments. So you cannot use this CLI to confirm whether a message has a file uploaded — it will look empty even when Slack shows a video/image/file inline. To check attachments, drop to the direct Slack API (see below).

## Escape hatch: direct Slack API

When the CLI is missing a capability (channel create, member invite, message attachments, search beyond the wrapper, etc.), the credentials are right there on disk and you can hit `https://shopify.slack.com/api/<method>` directly.

### Where the credentials live

```bash
~/.config/agent-tools/agent-slack/credentials.json
```

Two fields:
- `token`  — `xoxc-...` browser session token.
- `cookie` — the URL-encoded `d` cookie (`xoxd-...`). xoxc tokens require this cookie to authenticate; using the token alone returns `not_authed`.

### Curl pattern

```bash
TOKEN=$(jq -r .token  ~/.config/agent-tools/agent-slack/credentials.json)
COOKIE=$(jq -r .cookie ~/.config/agent-tools/agent-slack/credentials.json)

curl -s "https://shopify.slack.com/api/conversations.history?channel=C0...&latest=1778149540.935289&inclusive=true&limit=1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Cookie: d=$COOKIE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  | python3 -m json.tool
```

For POST methods, send form-encoded body:

```bash
curl -s "https://shopify.slack.com/api/conversations.create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Cookie: d=$COOKIE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "name=tmp-river-video-heads-up" \
  --data-urlencode "is_private=true"
```

Use the workspace host (`shopify.slack.com/api/...`), not the generic `slack.com/api/...`. The xoxc/xoxd pair is workspace-bound.

### What this unlocks

Things the CLI cannot do but the API can, with this token:

- **Read full message metadata** — `conversations.history` / `conversations.replies` return `files`, `attachments`, `blocks`. Use this to verify a message actually has the attachment the author claims, before you tag 50 people who'll click a broken-looking post.
- **Create channels** — `conversations.create` (`is_private=true` for private).
- **Invite people to a channel** — `conversations.invite` with a comma-separated `users=` list (works in batches of ≤ ~1000 user IDs per call; for huge lists, chunk it).
- **Open a multi-person DM (mpim)** — `conversations.open` with a comma-separated `users=` list. **Slack hard-caps mpims at 9 members total (you + 8 others)** — this is a product limit, not an API one. Anything larger has to be a private channel.
- **Upload files** — `files.getUploadURLExternal` + PUT + `files.completeUploadExternal`. Three-step flow; use only when the user explicitly asks.
- **Edit / delete messages** — `chat.update` / `chat.delete`. Same safety rules apply: a delete is recovery from your own mistake, not a routine tool.

### Safety rules carry over

The direct API does **not** unlock looser behavior. The mandatory safety rules at the top of this skill apply equally to anything you do with curl:

- Test only in `#surma-river`.
- Confirm destination before every real send / channel create / invite.
- Get it right the first time — each curl call is a real action against the real workspace.
- Don't probe "what happens if I call X" against real channels or DMs.

A sent message via curl is just as un-deletable (without `chat.delete`, which is itself a real action) as one sent via the CLI. Treat the API access as a capability extension, not a safety bypass.
