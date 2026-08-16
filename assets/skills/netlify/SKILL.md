---
name: netlify
description: Deploy sites and manage Netlify resources via the Netlify CLI and REST API. Use when the user asks to deploy a site, list sites, check deploy status, manage environment variables, or perform any Netlify operation.
compatibility: Requires a Netlify personal access token at /var/lib/credentials/scout/netlify-token.
---

# Netlify Management

Deploy sites and manage Netlify resources via the CLI or REST API.

## Auth

The Netlify personal access token is stored at `/var/lib/credentials/scout/netlify-token`. The env var `NETLIFY_AUTH_TOKEN_FILE` points to this path.

**For the CLI:** export the token into `NETLIFY_AUTH_TOKEN` before each command.

```bash
export NETLIFY_AUTH_TOKEN=$(cat /var/lib/credentials/scout/netlify-token)
```

**For the REST API:** use a Bearer header.

```bash
NETLIFY_TOKEN=$(cat /var/lib/credentials/scout/netlify-token)
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" https://api.netlify.com/api/v1/...
```

## CLI usage

The CLI is not installed permanently. Run it via Nix:

```bash
export NETLIFY_AUTH_TOKEN=$(cat /var/lib/credentials/scout/netlify-token)
nix run nixpkgs#netlify-cli -- <command>
```

### Common commands

**List sites:**
```bash
nix run nixpkgs#netlify-cli -- sites:list
```

**Create a new site:**
```bash
nix run nixpkgs#netlify-cli -- sites:create --name my-site --account-slug surma
```

**Deploy a directory (draft):**
```bash
nix run nixpkgs#netlify-cli -- deploy --dir ./dist --site SITE_ID
```

**Deploy to production:**
```bash
nix run nixpkgs#netlify-cli -- deploy --dir ./dist --site SITE_ID --prod
```

**Check deploy status:**
```bash
nix run nixpkgs#netlify-cli -- status --site SITE_ID
```

**Set environment variables:**
```bash
nix run nixpkgs#netlify-cli -- env:set KEY value --site SITE_ID
```

**List environment variables:**
```bash
nix run nixpkgs#netlify-cli -- env:list --site SITE_ID
```

## REST API

Base URL: `https://api.netlify.com/api/v1`

### Sites

**List all sites:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/sites" | jq '.[].name'
```

**Get a site:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/sites/$SITE_ID"
```

**Create a site:**
```bash
curl -s -X POST -H "Authorization: Bearer $NETLIFY_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.netlify.com/api/v1/$ACCOUNT_SLUG/sites" \
  -d '{"name": "my-site"}'
```

**Delete a site:**
```bash
curl -s -X DELETE -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/sites/$SITE_ID"
```

### Deploys

**List deploys for a site:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/sites/$SITE_ID/deploys" | jq '.[0:5] | .[].state'
```

**Get a deploy:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/deploys/$DEPLOY_ID"
```

### DNS zones

**List DNS zones:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/dns_zones"
```

**List DNS records in a zone:**
```bash
curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
  "https://api.netlify.com/api/v1/dns_zones/$ZONE_ID/dns_records"
```

## Known accounts

- **Squoosh** — slug: `squoosh`, plan: Open Source
- **Surma's team** — slug: `surma`, plan: Free (default)

## Important notes

- The CLI takes several seconds to start via `nix run` because of Nix evaluation. Use the REST API for quick queries.
- `curl` is not on PATH in the Scout container. Use `nix run nixpkgs#curl -- <args>`.
- For directory deploys, the `--dir` flag points to the folder with the built static assets.
- Draft deploys (without `--prod`) create a unique preview URL without changing the production site.
- The `--site` flag accepts either a site ID or site name (e.g. `my-site.netlify.app`).
