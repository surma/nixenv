---
name: gws
description: Interact with Google Workspace APIs (Gmail, Drive, Sheets, Calendar, Docs, and more) via the `gws` CLI, and Google Maps/Places via the REST API. Use when the user asks to read or send email, manage Drive files, read or write spreadsheets, check calendar events, perform any Google Workspace operation, or search for places/restaurants/businesses on Google Maps.
compatibility: Requires the `gws` CLI to be installed and authenticated.
---

# Google Workspace CLI (`gws`)

Use this skill whenever you need to interact with Google Workspace services (Gmail, Drive, Sheets, Calendar, Docs, Slides, Tasks, People, Chat, and more) or the Google Maps/Places API.

## When to use

- The user asks to read, search, or send email
- The user asks to list, download, upload, or manage Drive files
- The user asks to read or write spreadsheet data
- The user asks about calendar events or scheduling
- Any task involving Google Workspace data
- The user asks to search for places, restaurants, or businesses
- The user asks for directions, place details, or ratings from Google Maps

## Verify the CLI

Before first use in a session, confirm the CLI is available and authenticated:

```bash
command -v gws
gws gmail users messages list --params '{"userId": "me", "maxResults": 1}'
```

If the second command returns an auth error, report it to the user — authentication is managed outside this session.

## Usage

```
gws <service> <resource> [sub-resource] <method> [flags]
```

### Services

| Service | Description |
|---|---|
| `gmail` | Send, read, and manage email |
| `drive` | Manage files, folders, and shared drives |
| `sheets` | Read and write spreadsheets |
| `calendar` | Manage calendars and events |
| `docs` | Read and write Google Docs |
| `slides` | Read and write presentations |
| `tasks` | Manage task lists and tasks |
| `people` | Manage contacts and profiles |
| `chat` | Manage Chat spaces and messages |
| `forms` | Read and write Google Forms |
| `keep` | Manage Google Keep notes |
| `meet` | Manage Google Meet conferences |
| `admin-reports` | Audit logs and usage reports |
| `script` | Manage Google Apps Script projects |
| `workflow` | Cross-service productivity workflows (alias: `wf`) |

### Common flags

| Flag | Purpose |
|---|---|
| `--params <JSON>` | URL/query parameters |
| `--json <JSON>` | Request body (POST/PATCH/PUT) |
| `--upload <PATH>` | Upload a local file (multipart) |
| `--upload-content-type <MIME>` | MIME type for upload (auto-detected if omitted) |
| `--output <PATH>` | Save binary response to a file |
| `--format <FMT>` | Output format: `json` (default), `table`, `yaml`, `csv` |
| `--page-all` | Auto-paginate (NDJSON, one JSON line per page) |
| `--page-limit <N>` | Max pages with `--page-all` (default: 10) |
| `--page-delay <MS>` | Delay between pages in ms (default: 100) |

## Discovering API shapes

**Always use `gws schema` before making a call you haven't made before.** It is cheaper than guessing parameters and getting errors.

```bash
# See available parameters for a method
gws schema gmail.users.messages.list

# Resolve nested $ref types in the schema
gws schema gmail.users.messages.send --resolve-refs
```

## Gmail

For Gmail, `userId` is almost always `"me"`.

### List messages

```bash
gws gmail users messages list --params '{"userId": "me", "maxResults": 10}'
```

### Search messages

Use Gmail's `q` parameter with standard Gmail search syntax:

```bash
gws gmail users messages list --params '{"userId": "me", "q": "from:alice@example.com subject:invoice", "maxResults": 5}'
```

### Read a message

The list endpoint only returns message IDs. To read content, fetch the full message:

```bash
gws gmail users messages get --params '{"userId": "me", "id": "<messageId>", "format": "full"}'
```

The response contains headers (From, To, Subject, Date) in `payload.headers` and body content in `payload.parts` or `payload.body`. Body data is base64url-encoded.

### Send an email

Construct an RFC 2822 message, base64url-encode it, and send:

```bash
# Build and encode the message
RAW=$(printf 'From: me\r\nTo: recipient@example.com\r\nSubject: Hello\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nBody text here' | base64 -w0 | tr '+/' '-_' | tr -d '=')

# Send it
gws gmail users messages send --params '{"userId": "me"}' --json "{\"raw\": \"$RAW\"}"
```

### Manage labels

```bash
gws gmail users labels list --params '{"userId": "me"}'
```

## Drive

### List files

```bash
gws drive files list --params '{"pageSize": 10}'
```

### Search files

```bash
gws drive files list --params '{"q": "name contains '\''report'\'' and mimeType = '\''application/pdf'\''", "pageSize": 10}'
```

### Download a file

```bash
gws drive files get --params '{"fileId": "<fileId>", "alt": "media"}' --output ./downloaded-file.pdf
```

### Upload a file

```bash
gws drive files create --json '{"name": "report.pdf"}' --upload ./report.pdf
```

## Sheets

### Read a spreadsheet

```bash
gws sheets spreadsheets get --params '{"spreadsheetId": "<id>"}'
```

### Read cell values

```bash
gws sheets spreadsheets values get --params '{"spreadsheetId": "<id>", "range": "Sheet1!A1:D10"}'
```

### Write cell values

```bash
gws sheets spreadsheets values update \
  --params '{"spreadsheetId": "<id>", "range": "Sheet1!A1", "valueInputOption": "USER_ENTERED"}' \
  --json '{"values": [["Hello", "World"], ["Row2Col1", "Row2Col2"]]}'
```

## Calendar

### List upcoming events

```bash
gws calendar events list --params '{"calendarId": "primary", "timeMin": "2026-01-01T00:00:00Z", "maxResults": 10, "singleEvents": true, "orderBy": "startTime"}'
```

### Create an event

```bash
gws calendar events insert --params '{"calendarId": "primary"}' --json '{
  "summary": "Meeting",
  "start": {"dateTime": "2026-04-23T10:00:00Z"},
  "end": {"dateTime": "2026-04-23T11:00:00Z"}
}'
```

## Pagination

For endpoints that return paginated results:

```bash
# Auto-paginate (returns NDJSON — one JSON object per page)
gws drive files list --params '{"pageSize": 100}' --page-all --page-limit 5

# Manual: use nextPageToken from the response
gws drive files list --params '{"pageSize": 100, "pageToken": "<token>"}'
```

## Tips

- **Use `gws schema` liberally** — it shows exactly which parameters a method accepts and what the request body looks like. This avoids trial and error.
- **Pipe to `jq`** for filtering and formatting: `gws gmail users messages list --params '{"userId": "me"}' | jq '.messages[:5]'`
- **Use `--format table`** for quick human-readable output when exploring.
- **Gmail message bodies are base64url-encoded** — decode with: `echo '<data>' | tr '_-' '/+' | base64 -d`
- **Drive file IDs** can be extracted from Google Docs/Sheets/Drive URLs: the ID is the long alphanumeric string in the URL path.

## Google Maps / Places API (New)

The `gws` CLI does not cover Google Maps, but the same OAuth credentials can be used to call the [Places API (New)](https://developers.google.com/maps/documentation/places/web-service/op-overview) directly via `curl`. The credentials file contains a `client_id`, `client_secret`, and `refresh_token` with the `cloud-platform` scope, which covers the Places API.

### Obtaining an access token

Every Places API call needs a Bearer token. Mint one from the refresh token:

```bash
CREDS=/var/lib/credentials/scout/gws-credentials.json
CLIENT_ID=$(jq -r .client_id "$CREDS")
CLIENT_SECRET=$(jq -r .client_secret "$CREDS")
REFRESH_TOKEN=$(jq -r .refresh_token "$CREDS")

ACCESS_TOKEN=$(nix shell nixpkgs#curl -c curl -s -X POST https://oauth2.googleapis.com/token \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN" \
  -d "grant_type=refresh_token" | jq -r '.access_token')
```

### Text search (find places by query)

```bash
nix shell nixpkgs#curl -c curl -s -X POST "https://places.googleapis.com/v1/places:searchText" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Goog-FieldMask: places.displayName,places.formattedAddress,places.rating,places.googleMapsUri,places.priceLevel,places.currentOpeningHours,places.websiteUri" \
  -d '{"textQuery": "Da Bucatino Rome"}' | jq .
```

### Nearby search

```bash
nix shell nixpkgs#curl -c curl -s -X POST "https://places.googleapis.com/v1/places:searchNearby" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Goog-FieldMask: places.displayName,places.formattedAddress,places.rating,places.googleMapsUri" \
  -d '{
    "includedTypes": ["restaurant"],
    "maxResultCount": 10,
    "locationRestriction": {
      "circle": {
        "center": {"latitude": 41.8902, "longitude": 12.4922},
        "radius": 500.0
      }
    }
  }' | jq .
```

### Get place details

Use a place ID returned from a search:

```bash
nix shell nixpkgs#curl -c curl -s \
  "https://places.googleapis.com/v1/places/PLACE_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Goog-FieldMask: displayName,formattedAddress,rating,reviews,currentOpeningHours,websiteUri,googleMapsUri,priceLevel" | jq .
```

### Field masks

The Places API (New) requires an `X-Goog-FieldMask` header to specify which fields to return. Common fields:

| Field | Description |
|---|---|
| `places.displayName` | Place name |
| `places.formattedAddress` | Full address |
| `places.rating` | Average rating (1-5) |
| `places.userRatingCount` | Number of ratings |
| `places.priceLevel` | Price level enum |
| `places.currentOpeningHours` | Current opening hours |
| `places.websiteUri` | Website URL |
| `places.googleMapsUri` | Google Maps link |
| `places.reviews` | User reviews |
| `places.location` | Lat/lng coordinates |
| `places.types` | Place type tags |

Use `*` as the field mask to return all fields (useful for exploration, but slower and more expensive).

### Tips

- **Always use `nix shell nixpkgs#curl -c curl ...`** since `curl` is not in the base environment.
- **The field mask is required** — omitting it returns an error.
- **Place IDs** from search results look like `places/ChIJ...` — pass the full string including the `places/` prefix to the details endpoint.
- **API reference:** https://developers.google.com/maps/documentation/places/web-service/op-overview
