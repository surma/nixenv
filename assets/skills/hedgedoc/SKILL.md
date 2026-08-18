---
name: hedgedoc
description: Find, read, and update Surma's HedgeDoc 2 notes through the authenticated API. Use when the user asks about HedgeDoc notes or requests note changes.
compatibility: Requires access to HedgeDoc 2 and a token at /var/lib/credentials/scout/hedgedoc-token.
---

# HedgeDoc 2 Notes

Use the internal API for Surma's HedgeDoc 2 instance.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN_FILE="/var/lib/credentials/scout/hedgedoc-token"
HD_TOKEN=$(cat "$HD_TOKEN_FILE")
```

Set these variables in each shell command. Shell state does not persist between tool calls.

## Safety

- Read the token from its file for each task.
- Never print the token or include it in messages, logs, or repository files.
- Send the token only to the exact internal base URL above.
- Make only read requests unless the user explicitly requests a change.
- Resolve exactly one note before an update.
- Fetch the latest content immediately before an update.
- The `PUT` route replaces the complete note.
- Never retry an update until you inspect the current live content.
- Never delete a note unless the user explicitly requests that deletion.

## Verify access

Use the token to fetch the account identity.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)

me_json=$(
  nix run nixpkgs#curl -- \
    --silent --show-error --fail-with-body \
    --header "Authorization: Bearer $HD_TOKEN" \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/me"
)
printf '%s\n' "$me_json" | jq '.'
```

A `401` response means that the token is absent, invalid, or revoked.

## Find a note

The account endpoint returns metadata for all notes that Surma owns.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)

notes_json=$(
  nix run nixpkgs#curl -- \
    --silent --show-error --fail-with-body \
    --header "Authorization: Bearer $HD_TOKEN" \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/me/notes"
)
printf '%s\n' "$notes_json" | jq '.'
```

Each result contains a title and a `primaryAlias`. Use the alias for later requests.

Match a title exactly and count the results.

```bash
TITLE="TODO"
matches_json=$(jq --arg title "$TITLE" '[.[] | select(.title == $title)]' <<<"$notes_json")
printf '%s\n' "$matches_json" | jq '.'
match_count=$(jq 'length' <<<"$matches_json")
```

If the count is not one, stop and ask for a note URL or alias. Do not choose between duplicate titles.

The account endpoint does not list notes that another user owns. For such notes, ask for the note URL or alias.

## Read a note

Fetch metadata when you need ownership, permissions, aliases, or version information.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)
ALIAS="replace-with-primary-alias"

metadata_json=$(
  nix run nixpkgs#curl -- \
    --silent --show-error --fail-with-body \
    --header "Authorization: Bearer $HD_TOKEN" \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/notes/$ALIAS/metadata"
)
printf '%s\n' "$metadata_json" | jq '.'
```

Fetch the raw Markdown when you need the note content.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)
ALIAS="replace-with-primary-alias"

nix run nixpkgs#curl -- \
  --silent --show-error --fail-with-body \
  --header "Authorization: Bearer $HD_TOKEN" \
  --header "Accept: text/markdown" \
  "$HD_BASE_URL/api/v2/notes/$ALIAS/content"
```

## Update a note

First, fetch the latest Markdown into a new file inside the current working directory. Check that the path does not exist.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)
ALIAS="replace-with-primary-alias"
NOTE_FILE="$PWD/hedgedoc-$ALIAS.md"

test ! -e "$NOTE_FILE"
nix run nixpkgs#curl -- \
  --silent --show-error --fail-with-body \
  --header "Authorization: Bearer $HD_TOKEN" \
  --header "Accept: text/markdown" \
  --output "$NOTE_FILE" \
  "$HD_BASE_URL/api/v2/notes/$ALIAS/content"
```

Read the file before you edit it. Change only the text that the user requested.

Send the complete updated Markdown with `PUT`.

```bash
HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN=$(cat /var/lib/credentials/scout/hedgedoc-token)
ALIAS="replace-with-primary-alias"
NOTE_FILE="$PWD/hedgedoc-$ALIAS.md"

update_json=$(
  nix run nixpkgs#curl -- \
    --silent --show-error --fail-with-body \
    --request PUT \
    --header "Authorization: Bearer $HD_TOKEN" \
    --header "Content-Type: text/markdown" \
    --header "Accept: application/json" \
    --data-binary "@$NOTE_FILE" \
    "$HD_BASE_URL/api/v2/notes/$ALIAS"
)
printf '%s\n' "$update_json" | jq '{metadata, content}'
```

Fetch the live content again after the update. Verify the requested change and the surrounding text.

HedgeDoc can remove a final newline. Treat that normalization as equivalent after you inspect the difference.

If verification differs for another reason, stop. Read the live note before you consider another update.

Remove only the temporary note files that this workflow created.
