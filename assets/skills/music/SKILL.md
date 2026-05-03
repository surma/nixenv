---
name: music
description: Browse and manage Surma's personal music collection. Use when the user asks about their music library, wants recommendations cross-checked against what they own, asks to add albums, search for downloads, import into Lidarr, or check their Spotify library. Covers Navidrome (playback/library), Lidarr (collection management), Prowlarr (torrent search), qBittorrent (downloads), and Spotify (external library).
compatibility: Requires network access to Nexus services and credential files under /var/lib/credentials/scout/.
---

# Music

Use this skill to interact with Surma's personal music infrastructure. The
stack runs on Nexus and consists of five services:

- **Navidrome** — music server and player (Subsonic API)
- **Lidarr** — album collection manager (adds artists, monitors albums, imports files)
- **Prowlarr** — torrent indexer aggregator (searches multiple trackers)
- **qBittorrent** — torrent client (downloads)
- **Spotify** — external library reference via `spotify_player` CLI

## Service URLs and credentials

All services run on Nexus at `*.nexus.hosts.10.0.0.2.nip.io`. Credentials
are bind-mounted read-only at `/var/lib/credentials/scout/`.

| Service | Base URL | Credential file |
|---|---|---|
| Navidrome | `http://music.nexus.hosts.10.0.0.2.nip.io` | `navidrome-password` |
| Lidarr | `http://lidarr.nexus.hosts.10.0.0.2.nip.io` | `lidarr-api-key` |
| Prowlarr | `http://prowlarr.nexus.hosts.10.0.0.2.nip.io` | `prowlarr-api-key` |
| qBittorrent | `http://torrent.nexus.hosts.10.0.0.2.nip.io` | (auth whitelisted by subnet) |

## Navidrome — browsing the music library

Navidrome exposes the Subsonic API. Use it to check what's in the local music
collection, get play counts, search for artists/albums, and verify imports.

```bash
NAVIDROME_PASS=$(cat /var/lib/credentials/scout/navidrome-password)
BASE="http://music.nexus.hosts.10.0.0.2.nip.io/rest"
AUTH="u=surma&p=$NAVIDROME_PASS&v=1.16.1&c=scout&f=json"

# Search for an artist
curl -s "$BASE/search3?$AUTH&query=Floating+Points&artistCount=5&albumCount=5&songCount=0"

# Get artist details
curl -s "$BASE/getArtist?$AUTH&id=<artistId>"

# Get an album's tracks
curl -s "$BASE/getAlbum?$AUTH&id=<albumId>"

# Get top songs by play count
curl -s "$BASE/getTopSongs?$AUTH&artist=Caravan+Palace&count=50"

# Get recently played
curl -s "$BASE/getAlbumList2?$AUTH&type=recent&size=20"

# Get all artists
curl -s "$BASE/getArtists?$AUTH"
```

All responses are JSON under `.["subsonic-response"]`.

### Cross-checking recommendations

When recommending music, always verify against both Navidrome (local
collection) and Spotify (external library) before presenting recommendations
as "new." The user has explicitly asked for this.

## Lidarr — collection management

Lidarr manages the music library: adding artists, monitoring albums, triggering
searches, and importing downloaded files.

```bash
LIDARR_KEY=$(cat /var/lib/credentials/scout/lidarr-api-key)
LIDARR="http://lidarr.nexus.hosts.10.0.0.2.nip.io/api/v1"
AUTH="-H 'X-Api-Key: $LIDARR_KEY'"

# Search for an artist to add
curl -s "$LIDARR/artist/lookup?term=Bonobo" $AUTH

# Get all artists
curl -s "$LIDARR/artist" $AUTH

# Get a specific artist
curl -s "$LIDARR/artist/<id>" $AUTH

# Get albums for an artist
curl -s "$LIDARR/album?artistId=<id>" $AUTH

# Add an artist (monitor: none — then selectively monitor albums)
curl -s -X POST "$LIDARR/artist" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "foreignArtistId": "<musicbrainz-id>",
    "qualityProfileId": 2,
    "rootFolderPath": "/dump/music",
    "monitored": false,
    "addOptions": {"monitor": "none"}
  }'

# Monitor a specific album
curl -s -X PUT "$LIDARR/album/monitor" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"albumIds": [<albumId>], "monitored": true}'

# Search for a monitored album
curl -s -X POST "$LIDARR/command" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"name": "AlbumSearch", "albumIds": [<albumId>]}'

# Refresh artist metadata (fixes missing releases)
curl -s -X POST "$LIDARR/command" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"name": "RefreshArtist", "artistId": <id>}'

# Trigger completed download scan
curl -s -X POST "$LIDARR/command" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"name": "DownloadedAlbumsScan"}'

# Check queue (downloads in progress / stuck imports)
curl -s "$LIDARR/queue?includeArtist=true&includeAlbum=true&pageSize=50" $AUTH
```

### Quality profile

Quality profile 2 is configured as "Lossless + MP3-320 Fallback." It's applied
to all artists. Preferred quality order: FLAC > MP3-320. Do not accept other
formats.

### Adding artists — important conventions

- When the user asks to add a recommended album, add **only that specific
  album**, not the whole discography, unless explicitly asked.
- Add the artist with `"addOptions": {"monitor": "none"}`, then selectively
  monitor the specific album(s).
- Always use quality profile 2.
- Root folder is `/dump/music`.

### Manual import via API

Lidarr's auto-import frequently fails for RuTracker downloads. Use the manual
import API:

```bash
# 1. Get import preview (Lidarr evaluates each file)
curl -s "$LIDARR/manualimport?folder=<download-path>&artistId=<id>&albumId=<id>&filterExistingFiles=false" $AUTH

# 2. Build payload from the preview response and submit
curl -s -X POST "$LIDARR/command" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"name": "ManualImport", "files": [...], "importMode": "copy"}'
```

Each file in the payload needs: `path`, `artistId`, `albumId`,
`albumReleaseId`, `trackIds`, `quality`, `indexerFlags`,
`disableReleaseSwitching`.

### Common issues

- **Album has no releases (empty track list):** Run `RefreshArtist` to pull
  metadata from MusicBrainz. This fixes the most common import failure.
- **Import fails with "Couldn't find similar album":** Usually caused by
  missing release data. Refresh the artist, then retry with manual import.
- **Track count mismatch:** Check MusicBrainz releases directly
  (`musicbrainz.org/ws/2/release-group/<id>?inc=releases&fmt=json`). Some
  albums have bonus-track editions (e.g. JP releases). Select the correct
  release in the manual import.
- **"database is locked" SQLite errors:** Intermittent Lidarr issue. Retry
  after a few seconds.

## Prowlarr — searching for torrents

Prowlarr aggregates multiple torrent indexers. Use it when Lidarr's automatic
search fails to find a release.

```bash
PROWLARR_KEY=$(cat /var/lib/credentials/scout/prowlarr-api-key)
PROWLARR="http://prowlarr.nexus.hosts.10.0.0.2.nip.io/api/v1"

# Search across all indexers
curl -s "$PROWLARR/search?query=Floating+Points+Crush+FLAC&type=search" \
  -H "X-Api-Key: $PROWLARR_KEY"
```

Results include `downloadUrl`, `seeders`, `size`, `indexer`, and `title`.
Filter for FLAC releases with good seeder counts.

### Downloading via qBittorrent

```bash
QBIT="http://torrent.nexus.hosts.10.0.0.2.nip.io/api/v2"

# Add a torrent (use default save path — custom paths cause permission errors)
curl -s -X POST "$QBIT/torrents/add" \
  -F "urls=<torrent-url>" \
  -F "category=lidarr"

# Check torrent status
curl -s "$QBIT/torrents/info?category=lidarr" | jq '.[] | {name, state, progress}'
```

**Important:** Always use qBittorrent's default save path
(`/dump/state/qbittorrent/qBittorrent/downloads`). Custom paths under
`/dump/music/tmp/` cause "Permission denied" errors.

### RuTracker torrents

RuTracker download URLs work with qBittorrent. Tracker URLs like
`bt.t-ru.org`, `bt3.t-ru.org`, `bt4.t-ru.org` are all functional.
RuTracker results often have the best lossless quality (24-bit FLAC).

### LimeTorrents warning

LimeTorrents download URLs return invalid files (not actual `.torrent`
format). Avoid this indexer.

## Spotify — external library reference

Use `spotify_player` CLI to browse the user's Spotify library. This is
primarily for cross-referencing recommendations — checking what the user
already knows or has saved in Spotify before suggesting "new" music.

Credentials are set up automatically via Home Manager activation (copied from
`/var/lib/credentials/scout/` to `~/.cache/spotify-player/`).

```bash
# List saved albums (JSON array)
spotify_player get key user-saved-albums

# List followed artists
spotify_player get key user-followed-artists

# List playlists
spotify_player get key user-playlists

# List liked tracks
spotify_player get key user-liked-tracks

# List top tracks
spotify_player get key user-top-tracks

# Search Spotify catalog
spotify_player search "Bonobo Dial M for Monkey"
```

### Cross-checking workflow

When making recommendations:

1. Check Navidrome (local collection) for artist/album presence
2. Check Spotify (`user-saved-albums`) for artist/album presence
3. Only present as "new" if absent from both
4. Clearly distinguish between "not in local collection" and "not in Spotify either"

### Token refresh

`spotify_player` handles token refresh automatically using the stored
credentials. If auth errors occur, the user needs to re-authenticate on their
laptop and send updated credential files.

## Recommended workflows

### Add a new album to the collection

1. Search Lidarr for the artist: `artist/lookup?term=<name>`
2. Add the artist (monitor: none, quality profile 2)
3. Refresh artist metadata: `RefreshArtist`
4. Find the specific album and monitor it
5. Try Lidarr's automatic search first: `AlbumSearch`
6. If that fails, search Prowlarr manually for a FLAC torrent
7. Add the torrent to qBittorrent with category `lidarr`
8. Wait for download, then trigger `DownloadedAlbumsScan`
9. If auto-import fails, use the manual import API
10. Verify in Navidrome that the album appears with correct tracks

### Check what the user has

```bash
# Local collection (Navidrome)
curl -s "$BASE/search3?$AUTH&query=<artist>&artistCount=5&albumCount=10&songCount=0"

# Spotify
spotify_player get key user-saved-albums | python3 -c "
import json, sys
for a in json.load(sys.stdin):
    artists = ', '.join(ar['name'] for ar in a.get('artists', []))
    if '<artist>'.lower() in artists.lower():
        print(f'{artists} - {a[\"name\"]}')
"
```

## Tips

- FLAC image+cue downloads are acceptable — the user has a splitter script.
- The user's Navidrome username is `surma`.
- Always use `jq` to parse API responses.
- When checking MusicBrainz directly, use `User-Agent: Scout/1.0 (surma@surma.dev)` and respect their 1-request-per-second rate limit.
- Lidarr artist/album IDs are internal — they don't correspond to MusicBrainz IDs. Use `foreignArtistId` / `foreignAlbumId` for MusicBrainz lookups.
