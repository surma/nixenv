---
name: whatsapp
description: Read and send WhatsApp messages via the `whatsapp-cli` tool (eddmann/whatsapp-cli). Use when the user asks to read, search, or send WhatsApp messages, list chats or contacts, or manage their WhatsApp session.
compatibility: Requires `whatsapp-cli` to be installed and an authenticated session at ~/.config/whatsapp-cli/.
---

# WhatsApp CLI

Use this skill to interact with the user's WhatsApp account via `whatsapp-cli` (eddmann/whatsapp-cli).

The CLI connects as a linked device using the WhatsApp Web multi-device protocol. The session is stored locally and lasts approximately 20 days before re-authentication is needed.

## Verify the CLI

Before first use in a session, confirm the CLI is available and the session is active:

```bash
command -v whatsapp-cli
whatsapp-cli chats --store ~/.config/whatsapp-cli
```

If `chats` returns empty data or an auth error, the session may have expired. Follow the **Re-authentication** section below.

## Store location

The default store is `~/.config/whatsapp-cli/`. Always pass `--store ~/.config/whatsapp-cli` to every command.

## Usage

### List chats

```bash
whatsapp-cli chats --store ~/.config/whatsapp-cli
whatsapp-cli chats --groups --store ~/.config/whatsapp-cli
```

### Read messages

```bash
whatsapp-cli messages <jid> --store ~/.config/whatsapp-cli
whatsapp-cli messages <jid> --limit 20 --store ~/.config/whatsapp-cli
whatsapp-cli messages <jid> --timeframe today --store ~/.config/whatsapp-cli
```

Timeframe options: `last_hour`, `today`, `yesterday`, `last_3_days`, `this_week`, `last_week`, `this_month`.

### Search messages

```bash
whatsapp-cli search "keyword" --store ~/.config/whatsapp-cli
whatsapp-cli search "keyword" --chat <jid> --store ~/.config/whatsapp-cli
```

### Send a message

```bash
whatsapp-cli send <jid> "message text" --store ~/.config/whatsapp-cli
whatsapp-cli send <jid> --file photo.jpg --caption "Check this" --store ~/.config/whatsapp-cli
```

### Sync (receive new messages)

One-shot sync:
```bash
whatsapp-cli sync --store ~/.config/whatsapp-cli
```

Continuous sync (daemon mode):
```bash
whatsapp-cli sync --follow --store ~/.config/whatsapp-cli
```

### Other commands

```bash
whatsapp-cli contacts --store ~/.config/whatsapp-cli
whatsapp-cli groups --store ~/.config/whatsapp-cli
whatsapp-cli download <msg-id> --chat <jid> --store ~/.config/whatsapp-cli
whatsapp-cli react <msg-id> "thumbsup" --chat <jid> --store ~/.config/whatsapp-cli
```

## Output formats

Use `--format` to control output: `json` (default), `jsonl`, `csv`, `tsv`, `human`.

```bash
whatsapp-cli chats --format human --store ~/.config/whatsapp-cli
```

## JID format

WhatsApp JIDs (chat identifiers) look like:
- Individual: `<country><number>@s.whatsapp.net` (e.g. `447774333068@s.whatsapp.net`)
- Group: `<id>@g.us`
- LID (linked identity): `<id>@lid` — WhatsApp's internal identifier, maps to a phone JID

Use `chats` or `contacts` to discover JIDs.

To look up a phone number's LID or vice versa, query the session DB:
```bash
sqlite3 ~/.config/whatsapp-cli/store/session.db "SELECT * FROM whatsmeow_lid_map WHERE pn='<phone-number>';"
```

## History sync and backfill

### How the initial sync works

After pairing, WhatsApp sends history in chunks. The initial sync typically delivers a small fraction of total messages. Our patched build sets `RequireFullSync=true` and `OnDemandReady=true` in the device registration to request more history.

**Critical:** The user's phone must have WhatsApp **open and in the foreground** during sync. The phone is the source of history data — if it's locked or WhatsApp is backgrounded, sync stalls.

To maximize initial sync data, run `sync --follow` immediately after auth and keep it running:
```bash
whatsapp-cli sync --follow --store ~/.config/whatsapp-cli
```

### Checking what the server knows about

The CLI's `messages.db` only contains messages where content was delivered. But WhatsApp may have sent **message secret keys** (encryption references) for many more chats. Check the session DB:

```bash
# All chats the server knows about (even without message content):
sqlite3 ~/.config/whatsapp-cli/store/session.db \
  "SELECT chat_jid, COUNT(*) as cnt FROM whatsmeow_message_secrets GROUP BY chat_jid ORDER BY cnt DESC;"

# Contacts with names:
sqlite3 ~/.config/whatsapp-cli/store/session.db \
  "SELECT their_jid, full_name, push_name FROM whatsmeow_contacts;"
```

This is useful when a chat doesn't appear in `whatsapp-cli chats` — it may still exist in the session DB with secret keys but no delivered content.

### On-demand backfill (pulling older messages)

The `backfill` command requests older messages for a chat you already have messages in. It requires a **real message ID** as an anchor point.

**Important constraints:**
- The anchor message must be a **received** message (`is_from_me=0`). Sent messages don't work as anchors.
- The user's phone must have WhatsApp **open** for the phone to respond.
- Each request returns ~50 messages going further back in time.
- Chain multiple requests to go deeper: after each batch, use the new oldest message as the next anchor.

```bash
whatsapp-cli backfill <jid> --count 50 --store ~/.config/whatsapp-cli
```

Note: the built-in `backfill` command works but the CLI doesn't wait for the response or chain requests. For deeper backfill, there is a standalone `do-backfill` tool at `/tmp/do-backfill` that:
- Takes a store dir, chat JID, message ID, and unix timestamp
- Sends the on-demand history request
- Persists received messages directly to `messages.db`
- Prints results

Usage:
```bash
# Get oldest received message as anchor
sqlite3 ~/.config/whatsapp-cli/store/messages.db \
  "SELECT id, strftime('%s', timestamp) FROM messages WHERE chat_jid='<jid>' AND is_from_me=0 ORDER BY timestamp ASC LIMIT 1;"

# Request 50 messages before that anchor
/tmp/do-backfill ~/.config/whatsapp-cli "<jid>" "<msg-id>" "<unix-timestamp>" 50
```

Chain requests by re-querying the oldest message after each round.

### Chats with no messages (placeholder problem)

Some chats have message secret keys in the session DB but no content in `messages.db`. This happens when:
1. The history sync delivered only encryption keys (placeholders), not message content
2. The websocket connection dropped before content chunks arrived

Currently there is no reliable way to fetch content for placeholder-only chats. The workaround is to have a new message sent in that chat (even a short one), which triggers live sync and creates an anchor for on-demand backfill.

### Websocket EOF errors

The connection frequently drops with `failed to read frame header: EOF`. This is a known whatsmeow issue in server/container environments. It doesn't corrupt the session — just reconnect. For long-running syncs, use `--follow` mode which auto-reconnects, or restart manually.

## Re-authentication (QR code rescan)

Sessions last ~20 days. When expired, the CLI will fail to connect. Since Scout runs in a container without a display, QR code pairing must be relayed to the user via Telegram.

### Procedure

**IMPORTANT:** The user must be able to scan a QR code on their phone. If they are only on mobile, this will not work — they need a second device to view the QR image from Telegram while scanning with their phone's WhatsApp.

#### Option A: Pair from the container (preferred)

Pairing directly from the container works with the eddmann CLI — its `auth login` does an initial sync as part of the auth flow, which completes the handshake. See Option B below for the QR capture procedure. After successful auth, immediately run `sync --follow` with the phone's WhatsApp open to maximize history delivery.

#### Option B: User authenticates locally (fallback)

If pairing from the container fails repeatedly, ask the user to run on their own machine:

```bash
nix run 'git+ssh://git@github.com/surma/nixenv#whatsapp-cli' -- auth login --store ~/wa-store
```

Then have them send the resulting `~/wa-store` directory (tar it up) via Telegram.
Extract and copy to `~/.config/whatsapp-cli/`:

```bash
# After receiving the tar.gz file:
nix shell nixpkgs#gnutar nixpkgs#gzip -c bash -c \
  'tar xzf <path-to-attachment> -C /tmp/ && \
   rm -rf ~/.config/whatsapp-cli/store && \
   cp -r /tmp/wa-store/store ~/.config/whatsapp-cli/store'
```

Verify with `whatsapp-cli chats --store ~/.config/whatsapp-cli`.

#### Option C: QR via Telegram (for container pairing)

This is the QR capture procedure used by Option A. It can be fragile because:
- QR codes expire in ~30 seconds and regenerate
- The QR must be captured, converted to an image, and sent before it expires
- Multiple failed scan attempts trigger WhatsApp rate limiting (~30-60 min cooldown)

Steps:

1. Ensure `qr2png.py` (bundled with this skill) and Pillow are available:
   ```bash
   QR2PNG="$(dirname "$(readlink -f ~/.agents/skills/whatsapp/SKILL.md)")/qr2png.py"
   ```

2. Start auth, capture QR, convert to PNG, send via Telegram — all in quick succession:
   ```bash
   rm -rf /tmp/wa-auth-store /tmp/wa-qr.txt /tmp/wa-qr.png
   mkdir -p /tmp/wa-auth-store

   whatsapp-cli auth login --store /tmp/wa-auth-store > /tmp/wa-qr.txt 2>&1 &
   AUTH_PID=$!
   sleep 6

   NIX_PATH=nixpkgs=flake:nixpkgs nix-shell \
     -p 'python3.withPackages(ps: [ps.pillow])' \
     --run "python3 $QR2PNG /tmp/wa-qr.txt /tmp/wa-qr.png"
   ```

3. Immediately send `/tmp/wa-qr.png` to the user via `scout_send_file` with an urgent caption telling them to scan now.

4. Monitor the auth process for success or a new QR:
   ```bash
   for i in $(seq 1 60); do
     sleep 2
     if ! kill -0 $AUTH_PID 2>/dev/null; then break; fi
     LINES=$(wc -l < /tmp/wa-qr.txt)
     grep -q "Successfully" /tmp/wa-qr.txt && break
   done
   grep -v '█\|▀\|▄' /tmp/wa-qr.txt
   ```

5. If auth succeeds, copy the session:
   ```bash
   rm -rf ~/.config/whatsapp-cli/store
   cp -r /tmp/wa-auth-store/store ~/.config/whatsapp-cli/store
   ```

6. If the QR expired (new QR block appears in the output), re-run the `qr2png.py` conversion and resend the image. The auth process stays running and generates new QR codes automatically.

7. If the user's phone says "couldn't link device, try again later", this is a rate limit. Wait 30-60 minutes before retrying.

### Known issues

- **Server-side pairing failures:** Pairing from the container can fail with the vicentereig CLI (the phone shows "couldn't log in" after a 30-second spinner). The eddmann CLI works because its `auth login` command does an initial sync as part of the auth flow, which completes the handshake. If pairing fails, wait 30-60 minutes (rate limiting) before retrying. Option B (local auth) avoids server issues entirely.
- **Session expiry:** Sessions last ~20 days. After expiry, all commands will fail and re-authentication is required.
- **App state sync errors:** After fresh pairing, the first sync may fail with "didn't find app state key". This is transient; retry after a few seconds.
