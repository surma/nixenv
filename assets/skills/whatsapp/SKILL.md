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

Use `chats` or `contacts` to discover JIDs.

## Re-authentication (QR code rescan)

Sessions last ~20 days. When expired, the CLI will fail to connect. Since Scout runs in a container without a display, QR code pairing must be relayed to the user via Telegram.

### Procedure

**IMPORTANT:** The user must be able to scan a QR code on their phone. If they are only on mobile, this will not work — they need a second device to view the QR image from Telegram while scanning with their phone's WhatsApp.

#### Option A: User authenticates locally (preferred)

Ask the user to run on their own machine:

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

#### Option B: QR via Telegram (fallback)

Use this when the user cannot run the CLI locally. This is fragile because:
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

- **Server-side pairing failures:** Pairing from a server/container environment can fail even with correct credentials. The CLI reports "Successfully authenticated!" but the phone shows "couldn't log in" after a 30-second spinner. This is a known whatsmeow issue related to server detection by WhatsApp. Option A (local auth) avoids this entirely.
- **Session expiry:** Sessions last ~20 days. After expiry, all commands will fail and re-authentication is required.
- **App state sync errors:** After fresh pairing, the first sync may fail with "didn't find app state key". This is transient; retry after a few seconds.
