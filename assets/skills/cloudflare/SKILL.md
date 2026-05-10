---
name: cloudflare
description: Manage Cloudflare DNS records via the REST API. Use when the user asks to list, create, update, or delete DNS records, list zones/domains, or perform any Cloudflare DNS operation.
compatibility: Requires a Cloudflare API token at /var/lib/credentials/scout/cloudflare-api-token with Zone:DNS:Edit and Zone:Zone:Read permissions.
---

# Cloudflare DNS Management

Manage DNS records across Cloudflare zones using `curl` against the v4 REST API.

## Auth

```bash
CF_TOKEN=$(cat /var/lib/credentials/scout/cloudflare-api-token)
```

All requests use:
```
-H "Authorization: Bearer $CF_TOKEN"
-H "Content-Type: application/json"
```

## Zones (domains)

### List all zones

```bash
curl -s "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CF_TOKEN" | jq '.result[] | {name, id, status}'
```

Query params: `name` (exact), `status` (active/pending), `per_page` (max 50), `page`.

### Get zone ID by name

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?name=surma.dev" \
  -H "Authorization: Bearer $CF_TOKEN" | jq -r '.result[0].id'
```

## DNS Records

Base URL: `https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records`

### List records

```bash
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CF_TOKEN" | jq '.result[] | {id, type, name, content, proxied, ttl}'
```

Filter params:
- `type` — A, AAAA, CNAME, MX, TXT, NS, SRV, etc.
- `name` — exact FQDN (e.g. `www.surma.dev`)
- `name.contains` — substring match
- `content` — exact value (e.g. IP address)
- `per_page` — results per page (max 100, default 20)
- `page` — page number

### Create a record

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "sub.example.com",
    "content": "192.0.2.1",
    "ttl": 1,
    "proxied": true
  }'
```

Required fields: `type`, `name`, `content`.
Optional: `ttl` (1 = auto, 60–86400 seconds), `proxied` (default false), `comment`, `tags`.

Common record types:
- **A** — `content`: IPv4 address
- **AAAA** — `content`: IPv6 address
- **CNAME** — `content`: target hostname
- **MX** — `content`: mail server, also requires `priority` (integer)
- **TXT** — `content`: text value (quote-wrapped if needed)
- **SRV** — uses `data` object: `{service, proto, name, priority, weight, port, target}`

### Update a record (partial)

```bash
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "192.0.2.2"}'
```

Only include fields you want to change. Supports: `content`, `name`, `type`, `ttl`, `proxied`, `comment`, `tags`.

### Replace a record (full overwrite)

```bash
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "sub.example.com",
    "content": "192.0.2.2",
    "ttl": 3600,
    "proxied": false
  }'
```

### Delete a record

```bash
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_TOKEN"
```

### Get a single record

```bash
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_TOKEN" | jq '.result'
```

## Response format

All responses have this shape:
```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": { ... },
  "result_info": { "page": 1, "per_page": 20, "count": 5, "total_count": 5, "total_pages": 1 }
}
```

On error, `success` is `false` and `errors` contains `[{code, message}]`.

## Record object fields

| Field | Description |
|-------|-------------|
| `id` | Record identifier (used for update/delete) |
| `type` | A, AAAA, CNAME, MX, TXT, NS, SRV, etc. |
| `name` | Full DNS name (e.g. `www.surma.dev`) |
| `content` | Record value (IP, hostname, text) |
| `proxied` | Whether traffic goes through Cloudflare proxy |
| `ttl` | Time to live (1 = automatic) |
| `comment` | Optional note |
| `tags` | Optional string tags |
| `created_on` | ISO timestamp |
| `modified_on` | ISO timestamp |

## Known zones

| Domain | Zone ID |
|--------|---------|
| surma.dev | `ebf04a65eed7544d023aa5bdddd72f29` |
| surm.tech | `6003fa62b7c10cbb78b7b1976ae051a9` |
| surma.link | `4faa57afc9b72826db3cff3e1aeb0edb` |
| surma.technology | `65a73895585f2f7eaee8516702edfabb` |
| surmair.de | `f20da308aa776d231c8d82e477991053` |
| offthemainthread.tech | `723fdfaae17dc872bd503918bceeba81` |
| fewo5.eu | `6e4ba6ee45481efbc1fc956b0156d323` |
| slang.technology | `9e65eef02f2c0ef6dc3ff76e6f83dd48` |
| tinderforbananas.com | `98417361e812d77551f7fe2cd6ede7f2` |

## Important notes

- `curl` is not on PATH in the Scout container. Use `nix run nixpkgs#curl -- <args>`.
- Always read the token fresh: `CF_TOKEN=$(cat /var/lib/credentials/scout/cloudflare-api-token)`
- TTL=1 means "automatic" (Cloudflare picks optimal value, usually 300s).
- Proxied records (orange cloud) hide the origin IP and get Cloudflare CDN/WAF.
- Only A, AAAA, and CNAME records can be proxied.
- The `name` field in requests should be the full FQDN or just the subdomain part (CF appends the zone).
- Pagination: check `result_info.total_pages`; iterate with `page=2`, etc.
