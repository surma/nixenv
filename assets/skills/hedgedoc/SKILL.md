---
name: hedgedoc
description: Find, read, and update Surma's HedgeDoc 2 notes through the authenticated API. Use for HedgeDoc notes and Surma's personal to-do list.
compatibility: Requires access to HedgeDoc 2 and a token at /var/lib/credentials/scout/hedgedoc-token.
---

# HedgeDoc 2 Notes

Use the internal API for Surma's HedgeDoc 2 instance.

## Personal to-do list

Surma's personal to-do list is the note titled `TODO`. Use that exact title to find the note for each request.

Do not use Home Assistant for the personal to-do list. Home Assistant still contains Surma's shopping list.

Treat requests to add, complete, change, or remove to-do items as note updates. Preserve unrelated content and the existing Markdown structure.

## Command prelude

Start every HedgeDoc shell command with this block. Append the relevant command fragment below to the same shell call.

Shell state does not persist between tool calls.

```bash
set -euo pipefail

HD_BASE_URL="http://hedgedoc2.nexus.hosts.10.0.0.2.nip.io"
HD_TOKEN_FILE="/var/lib/credentials/scout/hedgedoc-token"
HD_TOKEN=$(cat "$HD_TOKEN_FILE")

hd_curl() {
  nix run nixpkgs#curl -- \
    --silent --show-error --fail-with-body \
    --header "Authorization: Bearer $HD_TOKEN" \
    "$@"
}
```

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
me_json=$(
  hd_curl \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/me"
)
printf '%s\n' "$me_json" | jq '.'
```

A `401` response means that the token is absent, invalid, or revoked.

## Find a note

The account endpoint returns metadata for all notes that Surma owns. Match the title exactly and count the results.

```bash
TITLE="exact note title"
notes_json=$(
  hd_curl \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/me/notes"
)
matches_json=$(jq --arg title "$TITLE" '[.[] | select(.title == $title)]' <<<"$notes_json")
match_count=$(jq 'length' <<<"$matches_json")
printf '%s\n' "$matches_json" | jq '.'
printf 'match_count=%s\n' "$match_count"
```

Each result contains a title and a `primaryAlias`. Use the alias for later requests.

If the count is not one, stop and ask for a note URL or alias. Do not choose between duplicate titles.

The account endpoint does not list notes that another user owns. For such notes, ask for the note URL or alias.

## Read a note

Fetch metadata when you need ownership, permissions, aliases, or version information.

```bash
ALIAS="replace-with-primary-alias"
metadata_json=$(
  hd_curl \
    --header "Accept: application/json" \
    "$HD_BASE_URL/api/v2/notes/$ALIAS/metadata"
)
printf '%s\n' "$metadata_json" | jq '.'
```

Fetch the raw Markdown when you need the note content.

```bash
ALIAS="replace-with-primary-alias"
hd_curl \
  --header "Accept: text/markdown" \
  "$HD_BASE_URL/api/v2/notes/$ALIAS/content"
```

## Update a note

First, fetch the latest Markdown into a new file inside the current working directory. Check that the path does not exist.

```bash
ALIAS="replace-with-primary-alias"
NOTE_FILE="$PWD/hedgedoc-$ALIAS.md"

test ! -e "$NOTE_FILE"
hd_curl \
  --header "Accept: text/markdown" \
  --output "$NOTE_FILE" \
  "$HD_BASE_URL/api/v2/notes/$ALIAS/content"
```

Read the file before you edit it. Change only the text that the user requested.

Send the complete updated Markdown with `PUT`.

```bash
ALIAS="replace-with-primary-alias"
NOTE_FILE="$PWD/hedgedoc-$ALIAS.md"

update_json=$(
  hd_curl \
    --request PUT \
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
