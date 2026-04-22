---
name: signal
description: Read and send Signal messages via `presage-cli` (whisperfish/presage). Use when the user asks to read, search, or send Signal messages, list chats or contacts, or manage their Signal session.
compatibility: Requires `presage-cli` to be installed and a linked session at ~/.config/presage/signal.db.
---

# Signal CLI (presage)

Use this skill to interact with the user's Signal account via `presage-cli` (whisperfish/presage), a Rust-based Signal client.

The CLI connects as a linked device using the Signal multi-device protocol. Messages are stored locally in a SQLite database.

## Verify the CLI

Before first use in a session, confirm the CLI is available and the session is active:

```bash
command -v presage-cli
presage-cli --sqlite-db-path ~/.config/presage/signal.db whoami
```

If `whoami` fails, the session may have expired or not been created. Follow the **Linking** section below.

## Store location

The database is at `~/.config/presage/signal.db`. Always pass `--sqlite-db-path ~/.config/presage/signal.db` to every command. The shorthand `$SIGNAL_DB` is not set automatically; use the full path.

## Usage

### List contacts

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db list-contacts
```

Output format: `<uuid> / <phone> / <name>`

Contacts are populated "on first sight" — they appear after messages are exchanged. Bulk contact sync from the primary device currently arrives empty (known presage limitation).

### List groups

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db list-groups
```

### Read messages

By recipient UUID:
```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db list-messages -u <service-id>
```

By group master key (hex):
```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db list-messages -k <group-master-key-hex>
```

With a start timestamp:
```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db list-messages -u <service-id> --from <unix-timestamp>
```

### Find a contact

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db find-contact -n "Name"
presage-cli --sqlite-db-path ~/.config/presage/signal.db find-contact -u <service-id>
presage-cli --sqlite-db-path ~/.config/presage/signal.db find-contact -p <phone-number>
```

### Send a message

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db send -u <service-id> "message text"
```

### Send to group

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db send-to-group -k <group-master-key-hex> "message text"
```

### Sync (receive new messages)

Run sync to receive all pending messages and store them in the database:

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db sync
```

This runs continuously until interrupted (Ctrl+C or SIGTERM). Both incoming and outgoing messages (via sync messages from the primary device) are stored.

### Retrieve a profile

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db retrieve-profile -u <service-id>
```

### Statistics

```bash
presage-cli --sqlite-db-path ~/.config/presage/signal.db stats
```

## Direct SQLite access

For reading messages without triggering read receipts or connecting to Signal, query the SQLite database directly:

```bash
sqlite3 ~/.config/presage/signal.db
```

### Key tables

- `contacts` — UUID (blob), phone_number, name, profile_key
- `threads` — id, group_master_key (NULL for 1:1), recipient_id
- `thread_messages` — ts, thread_id, sender_service_id, destination_service_id, content_body (protobuf blob)
- `groups` — group data
- `profiles` — cached profiles

### Useful queries

List all contacts:
```sql
SELECT hex(uuid), phone_number, name FROM contacts;
```

Count messages per thread:
```sql
SELECT t.id, c.name, COUNT(*) as msg_count
FROM thread_messages tm
JOIN threads t ON tm.thread_id = t.id
LEFT JOIN contacts c ON t.recipient_id = c.uuid
GROUP BY t.id ORDER BY msg_count DESC;
```

Recent messages (note: content_body is protobuf, not plain text; use presage-cli for readable output):
```sql
SELECT tm.ts, tm.sender_service_id, length(tm.content_body) as body_len
FROM thread_messages tm ORDER BY tm.ts DESC LIMIT 20;
```

### UUID format caveat

UUIDs are stored as **blobs** in `contacts` but as **text** in `thread_messages`. Direct joins require conversion:

```sql
-- This won't match:
SELECT * FROM thread_messages tm JOIN contacts c ON tm.sender_service_id = c.uuid;

-- Instead, compare hex representations or use presage-cli commands.
```

## Linking (QR code pairing)

### Prerequisites

The user must be able to scan a QR code with their phone's Signal app.

### Procedure

1. Generate a link URL and QR code:
   ```bash
   presage-cli --sqlite-db-path ~/.config/presage/signal.db link-device -n "Scout" > /tmp/presage-link.txt 2>/tmp/presage-link-err.txt &
   LINK_PID=$!
   sleep 4
   URI=$(grep "Alternatively" /tmp/presage-link.txt | sed 's/Alternatively, use the URL: //')
   nix shell nixpkgs#qrencode -c qrencode -o /tmp/signal-qr.png -s 8 -m 4 "$URI"
   ```

2. Send `/tmp/signal-qr.png` to the user via `scout_send_file` with an urgent caption.

3. The user scans with **Signal → Settings → Linked Devices → +**.

4. Monitor for completion:
   ```bash
   for i in $(seq 1 24); do
     sleep 5
     if ! kill -0 $LINK_PID 2>/dev/null; then
       echo "Done"
       grep "WhoAmI" /tmp/presage-link.txt && echo "Success!"
       break
     fi
   done
   ```

5. After linking, run `sync` to start receiving messages.

### Re-linking

If the session expires or the device is unlinked:
```bash
rm -f ~/.config/presage/signal.db*
```
Then follow the linking procedure again.

## Known issues

- **Bulk contacts sync is empty:** The contacts sync from the primary device runs but saves 0 contacts. Contacts are instead created "on first sight" when messages are exchanged. This is a presage bug with the current Signal contact sync format.
- **No history sync:** presage does not support Signal's 45-day message history transfer for linked devices. Only messages received after linking are stored.
- **content_body is protobuf:** The `thread_messages.content_body` column stores raw protobuf. Use `presage-cli list-messages` to get human-readable text, or decode the protobuf if needed.
- **sqlcipher warnings:** The `mlock()` warnings on startup are harmless (container lacks the `IPC_LOCK` capability).
- **Session expiry:** Signal may unlink devices that don't receive messages regularly. Run `sync` periodically to maintain the session.
