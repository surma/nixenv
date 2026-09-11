# Dynamic Access Management Rework — Implementation Plan

**Goal:** Replace static allowlists with runtime grants and a day-one admin web UI.

**Architecture:** Pylon performs packet forwarding only. Nexus terminates HTTPS for `*.apps.surma.technology` and the existing public domains. Nexus calls `surm-auth` with a Nix-declared logical app key. A persistent policy file stores stable identities, roles, and grants.

**Tech stack:** NixOS containers, Traefik, Cloudflare DNS-01, Go, GitHub OAuth, HS256 JWT cookies, age secrets, and nftables. The Go language directive remains 1.21 unless implementation requires otherwise. The reviewed lock selects Go 1.26.6 and Traefik 3.7.10.

**Approval boundary:** This document plans implementation. It does not authorize deployment, credential changes, data copies, or deletion. Each production operation needs explicit approval.

## 1. Scope and confirmed decisions

- Provide the authentication UI on day one.
- Preserve the existing public domains and the fixed GitHub callback.
- Add explicit public routes under `*.apps.surma.technology`.
- Keep aliases on the same logical app and policy as their primary domain.
- Use stable GitHub IDs now. Keep the provider interface extensible.
- Preserve trusted internal HTTP access on Nexus through port 8081.
- Preserve Gitea SSH, Minecraft, the Syncthing relay, and host administration.
- Accept a short coordinated maintenance outage for the two-host cutover.
- Preserve old generations, secrets, and state for a coordinated rollback.

Public publication requires an explicit logical app declaration and policy. A route does not imply unauthenticated access. A namespace setting does not publish every container port. No new route receives a default `authenticated` policy.

Shell alias-forwarding and SSH agent forwarding remain out of scope. Do not edit `profiles/home-manager/base.nix` or shell aliases. HTTP defaults in `modules/programs/gitea-cli/default.nix` are in scope. Its SSH fields remain unchanged.

The second OAuth provider, service tokens, and client-IP preservation remain out of scope. New HTTP/3 support also remains out of scope. Section 8 explicitly defines UDP forwarding without an HTTP/3 listener.

## 2. Current state and migration constraints

The review used commit `9345a14cf8f4cc8bd360bf475e7f558134b20c9f` on `scout/dynamic-service-access`.

- Pylon currently terminates HTTPS and runs `surm-auth` v1.
- `machines/pylon/default.nix` does not currently import `./service-nixos-admin.nix`. The file exists, but this configuration does not activate its localhost admin listener.
- Pylon proxies legacy domains to internal Nexus hostnames on HTTP port 80.
- Nexus currently serves internal routes on port 80 without TLS.
- Nexus currently trusts Pylon's forwarded headers because Pylon acts as an HTTP proxy.
- The current module enables auth from nonempty `allowedGitHubUsers` lists.
- The current app uses username-based JWT subjects and `_surm_auth` cookies.
- The current GitHub provider already obtains a numeric user ID.
- Brain runs separate private and public servers in one container.
- HedgeDoc intentionally shares one domain across its frontend and backend ports.
- LLM proxy, key receiver, and vendor proxy use three separate ports and domains.
- Nexus already consumes the LLM secrets through Scout and the key poller.
- Jellyfin and Jaeger declare Docker-provider routers outside the surmhosting service inventory.
- Citadel also imports surmhosting. Its internal routes and Minecraft container must still evaluate.

The existing Go dependencies support this design. Standard library additions alone do not require a new `vendorHash`.

**Supported deployment states:** old Nexus with old Pylon, and new Nexus with new Pylon.

**Unsupported transitional states:** new Nexus with old Pylon, and old Nexus with new Pylon. Both occur during the approved maintenance window. Neither state guarantees public service continuity.

Legacy YAML parsing does not make the v2 binary compatible with the v1 generation. Old generations retain their old binary and module. The new generation uses the complete v2 configuration.

## 3. Traffic and trust boundaries

### 3.1 Public traffic

```text
Internet client
  -> Pylon TCP 80/443 or UDP 80/443
  -> DNAT and source NAT over Tailscale
  -> Nexus TCP 80/443 or unused UDP 80/443
  -> Nexus Traefik HTTPS router
  -> surm-auth /auth?app=<declared-logical-app>, when policy requires auth
  -> the selected backend port
```

Pylon performs no HTTP parsing or TLS termination after cutover. Nexus sees Pylon's Tailscale address for public connections. Real client IPs are unavailable under this design.

Remove `forwardedHeaders.trustedIPs` from both public Nexus entrypoints. Set `forwardedHeaders.insecure = false`. Configure each public forward-auth middleware with `trustForwardHeader = false`. Do not preserve public trust for Pylon's address after it becomes a DNAT edge.

The plan needs no isolated legacy HTTP path. It accepts an outage instead. Therefore, it retains no forwarded-header trust exception.

Every restricted router calls a fixed middleware URL such as:

```nix
forwardAuth = {
  address = "http://10.202.0.2:8080/auth?app=hedgedoc2";
  trustForwardHeader = false;
  authRequestHeaders = [ "Cookie" ];
  authResponseHeaders = [ "X-Auth-Request-User" "X-Auth-Request-Email" ];
};
```

Traefik generates forward-auth request metadata from the request it actually routes. The middleware URL contains the logical app key from Nix, not the client's query string.

`surm-auth` requires exactly one known `app` query parameter. It never selects policy through `X-Forwarded-Host`, `Host`, or the redirect destination. Missing, duplicate, and unknown app keys fail closed.

Forwarded host and URI metadata serve only to reconstruct a return URL. Validate that URL against the selected app's domains. Reject malformed or cross-app metadata instead of changing the policy subject. Strip incoming identity headers before proxying protected requests. Accept identity headers only from successful forward-auth responses.

### 3.2 Internal traffic

Nexus serves internal HTTP routes on an explicit `internal` entrypoint at `:8081`. Those routes retain the `trusted-network` policy. They do not acquire GitHub authentication during this migration.

Allow TCP 8081 only from the existing trusted LAN and tailnet ranges:

```nix
networking.firewall.extraInputRules = ''
  ip saddr { 10.0.0.0/8, 100.64.0.0/10 } tcp dport 8081 accept comment "surmhosting internal HTTP"
'';
```

These IPv4 ranges include the existing container addresses. Do not rely on `ve-+` wildcard behavior in nftables. Do not add 8081 to unrestricted input ports.

Pylon forwards only the listed destination ports. A public HTTP `Host` cannot select an internal router on port 80 or 443. Direct container access remains inside the existing trusted network boundary.

Explicitly assign Docker-provider routers for Jellyfin and Jaeger to `internal`. Assign the Traefik dashboard to `internal`. Their exclusive entrypoint assignment implements the explicit `trusted-network` policy. Do not generate duplicate app routers for these provider-owned backends. Audit every provider's routers, not just the generated file-provider routes.

Keep Citadel's current internal port unchanged. The Nexus port change does not apply to `*.citadel.hosts.*`.

### 3.3 Domains and certificates

- Keep `auth.surma.technology` as the canonical login and callback host.
- Add `auth.apps.surma.technology` as an auth alias.
- Use explicit primary domains for each public logical app.
- Keep each legacy domain as an alias on that same app.
- Keep HedgeDoc and Gitea's application base URLs on their legacy domains during migration.
- Issue wildcard certificates for `*.apps.surma.technology` and `*.surma.technology`.
- Issue exact certificates for the three deeper `*.llm.surma.technology` names.

Aliases share policy, not separate grants. The cookie domain `.surma.technology` covers both listed namespaces. It does not cover unrelated registrable domains.

Day-one aliases stay inside `surma.technology`. Reject unrelated aliases in configuration rather than silently promising broken SSO. An unrelated secondary domain requires a separate session and certificate design before publication.

Inventory existing A and AAAA records before cutover. The new forwarding snippet is IPv4-only. An existing public AAAA record blocks cutover until an approved IPv6 path or DNS change resolves it. Do not silently drop existing IPv6 access.

## 4. Logical apps, routing schema, and initial policy

### 4.1 Schema contract

Add `services.<service>.expose.apps.<app>` under `services.surmhosting`. The service owns its container or host backend. Each logical app owns its ports, access policy, primary domain, and aliases.

The new app submodule has these fields:

```nix
# Shape of one expose.apps.<app> value.
{
  access.mode = "allowlist"; # required: internal | public | authenticated | allowlist
  access.seedUsers = [ "surma" ]; # optional, default []
  internal.enable = true; # default true
  internal.access = "trusted-network"; # required when internal.enable is true
  public.domain = "hedgedoc.apps.surma.technology"; # nullable, default null
  public.aliases = [ "hedgedoc.surma.technology" ]; # default []
  ports = [
    {
      port = 3000;
      hostname = "backend";
      internalRule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`) && (PathPrefix(`/realtime`) || PathPrefix(`/api`) || PathPrefix(`/public`) || PathPrefix(`/media`) || PathPrefix(`/uploads`) || PathPrefix(`/apidoc`))'';
      publicPathPrefixes = [ "/realtime" "/api" "/public" "/media" "/uploads" "/apidoc" ];
      publicPriority = 100;
    }
    {
      port = 3001;
      hostname = "frontend";
      internalRule = ''HostRegexp(`^hedgedoc2\.nexus\.hosts`)'';
      publicPathPrefixes = [];
      publicPriority = 1;
    }
  ];
}
```

Use `types.enum` for modes and `types.port` for ports. Use nullable strings for runtime paths and domain opt-outs where appropriate. Do not import runtime secret contents into the Nix store.

`access.mode` has no default. `public.domain = null` means no public router, never an automatically derived domain. `appsNamespace` validates names and selects certificates. It does not publish ports.

Update `expose.enable` to include nonempty `expose.apps`. Default `internalRule` to the existing hostname rule. Default `publicPathPrefixes` to an empty list and `publicPriority` to 1. Preserve existing backend selection, container names, and container service overrides.

Mode behavior:

- `internal`: emit internal routes only. Reject any public domain, aliases, or seed users.
- `public`: emit explicitly declared public routes without surm-auth middleware. Preserve the application's own authentication.
- `authenticated`: require a valid v2 session from any configured provider. No initial app uses this mode.
- `allowlist`: require a stable-ID grant or an admin role for public access.

An app with public mode requires a primary domain. Its internal route still has its separate explicit `trusted-network` policy. An app without internal routes must set `internal.enable = false`.

Public router rules combine the app's exact domain matches with the port's path prefixes. Empty prefixes mean the whole domain. A path rule cannot replace or bypass the domain condition.

Assertions must reject:

- Missing access policy on any new logical app.
- Public declarations on an internal-only app.
- Seed users on modes other than `allowlist`.
- Duplicate app keys across services.
- The same domain on different logical apps.
- The same domain repeated across primary and alias values.
- A logical app without ports.
- Old exposure fields mixed with `expose.apps` in one service.
- DNS challenge configuration without its environment file.

The same domain across HedgeDoc's two ports is valid because both ports belong to `hedgedoc2`. Brain's private and public ports must belong to different app keys. Each LLM port must belong to its own app key.

### 4.2 Compatibility and auth enablement

Keep old single-port and `expose.ports` declarations as internal-route shorthand for nonmigrated hosts with `appsNamespace = null`. They preserve those hosts' current router behavior. Do not generate public apps from this shorthand.

For Nexus with the namespace enabled, migrate every HTTP exposure to explicit logical apps. Reject an unresolved legacy HTTP exposure rather than publishing it implicitly.

Retain `expose.allowedGitHubUsers` temporarily as a seed adapter only. A nonempty list requires exactly one logical app with `access.mode = "allowlist"`. Reject multi-app ambiguity. The adapter maps the list to that app's `access.seedUsers`.

The adapter does not enable a v1 runtime, derive a public domain, or infer public access from an empty list. New Nexus declarations use explicit modes. Pylon's old generation remains the rollback artifact for v1.

Add `auth.enable` and explicitly set it to true on Nexus. Restricted public apps require it. Admin UI availability does not depend on legacy allowlists or the number of current grants.

### 4.3 Initial public inventory

Every restricted app below imports `surma` as a seed user. Resolve that username to its numeric GitHub ID before the initial policy commit. Use the same stable ID in the explicit bootstrap admin list.

- `hedgedoc2`: ports 3000 and 3001, `allowlist`. Primary `hedgedoc.apps.surma.technology`. Alias `hedgedoc.surma.technology`.
- `gitea`: existing HTTP port, `allowlist`. Primary `gitea.apps.surma.technology`. Alias `gitea.surma.technology`.
- `dump`: existing HTTP port, `allowlist`. Primary `dump.apps.surma.technology`. Alias `dump.surma.technology`.
- `brain`: private Brain port 8080, `allowlist`. Primary `brain.apps.surma.technology`. Alias `brain.surma.technology`.
- `scout-static`: existing HTTP port, `allowlist`. Primary `scout-static.apps.surma.technology`. Alias `scout-static.surma.technology`.
- `public-brain`: public Brain port 8081, `public`. Primary `public-brain.apps.surma.technology`. Alias `public-brain.surma.technology`.
- `music`: existing HTTP port, `public`. Primary `music.apps.surma.technology`. Alias `music.surma.technology`.
- `jazzy`: existing HTTP port, `public`. Primary `jazzy.apps.surma.technology`. Alias `jazzy-poisonous-plant-parlour.surma.technology`.
- `ha`: backend `100.97.65.42:8123`, `public`. Primary `ha.apps.surma.technology`. Alias `ha.surma.technology`.
- `proxy-llm`: port 4000, `public`. Primary `proxy-llm.apps.surma.technology`. Alias `proxy.llm.surma.technology`.
- `key-llm`: port 8080, `public`. Primary `key-llm.apps.surma.technology`. Alias `key.llm.surma.technology`.
- `vendors-llm`: port 4001, `public`. Primary `vendors-llm.apps.surma.technology`. Alias `vendors.llm.surma.technology`.

`public` means no additional GitHub gate. It does not disable Home Assistant, Navidrome, or LLM authentication. Test the existing backend authentication separately.

Auth is a special explicit route, not an application grant subject. Its login, callback, and health endpoints are public. Its admin endpoints require an admin session. Its mutating endpoints also require CSRF validation.

The policy key is always `hedgedoc2`, including grants, middleware, imports, tests, and UI links. The domain remains `hedgedoc.*`. Do not introduce a second `hedgedoc` policy key.

### 4.4 Initial internal-only inventory

The following services retain `access.mode = "internal"` and `internal.access = "trusted-network"`. They receive no public domain, aliases, or seed grants:

- `admin`, `copyparty`, `firefly`, and `firefly-imp`.
- `lidarr`, `prowlarr`, `radarr`, and `sonarr`.
- `overview`, `rss`, `syncthing`, `torrent`, and `voice-memos`.
- Docker-provider routes for Jellyfin and Jaeger.
- The Traefik dashboard.

This deliberately preserves their current exposure. A later public route requires its own explicit policy and approval. It must not appear through a namespace default.

Inventory backend ports from the evaluated current configuration. Do not assign invented port numbers or change application listener ports. In particular, preserve FreshRSS's internal-only boundary because its current `authType` is `none`.

## 5. surm-auth v2 design

### 5.1 Configuration

The module renders nonsecret topology into a generated YAML-compatible configuration. It can retain its current `builtins.toJSON` serialization. The file contains paths, never decrypted credentials.

```yaml
version: 2
server:
  address: "0.0.0.0:8080"
  base_url: "https://auth.surma.technology"
  auth_domains:
    - "auth.surma.technology"
    - "auth.apps.surma.technology"
session:
  cookie_name: "_surm_auth2"
  cookie_domain: ".surma.technology"
  cookie_secret_file: "/run/credentials/surm-auth.service/cookie-secret"
  cookie_secure: true
  duration: "168h"
policy:
  file: "/var/lib/surm-auth/policy.json"
audit:
  file: "/var/lib/surm-auth/audit.log"
providers:
  github:
    client_id_file: "/run/credentials/surm-auth.service/github-client-id"
    client_secret_file: "/run/credentials/surm-auth.service/github-client-secret"
bootstrap_admins:
  - provider: "github"
    id: "<verified-numeric-id>"
apps:
  hedgedoc2:
    mode: "allowlist"
    domains: ["hedgedoc.apps.surma.technology", "hedgedoc.surma.technology"]
    seed_users: ["surma"]
  brain:
    mode: "allowlist"
    domains: ["brain.apps.surma.technology", "brain.surma.technology"]
    seed_users: ["surma"]
  public-brain:
    mode: "public"
    domains: ["public-brain.apps.surma.technology", "public-brain.surma.technology"]
  rss:
    mode: "internal"
    domains: []
```

The placeholder ID above is illustrative. Production validation rejects placeholders and empty IDs.

The Go config shape must include the loaded secret fields:

```go
type SessionConfig struct {
    CookieName       string `yaml:"cookie_name"`
    CookieDomain     string `yaml:"cookie_domain"`
    CookieSecretFile string `yaml:"cookie_secret_file"`
    CookieSecret     string `yaml:"-"`
    CookieSecure     bool   `yaml:"cookie_secure"`
    Duration         string `yaml:"duration"`
}

type PolicyConfig struct {
    File string `yaml:"file"`
}

type AuditConfig struct {
    File string `yaml:"file"`
}
```

Keep loaded GitHub `ClientID` and `ClientSecret` fields with `yaml:"-"` tags. `LoadSecrets` populates all three values before constructors consume them.

Validate the version, policy paths, duration, provider, domain ownership, modes, and bootstrap IDs. Internal apps may have no domains. Public apps must have domains. The canonical base URL must use HTTPS and belong to `auth_domains`.

Reject legacy `oauth:` and `allowed_users` YAML with a clear migration error. Do not claim that aliases for those keys preserve v1 runtime compatibility. Nix supplies the v2 seed adapter before the new binary starts.

### 5.2 Policy persistence

Use one local JSON file with version 1 of the runtime policy schema:

```json
{
  "version": 1,
  "users": {
    "github:<verified-numeric-id>": {
      "provider": "github",
      "id": "<verified-numeric-id>",
      "username": "surma",
      "role": "admin",
      "first_seen": "2026-09-10T12:00:00Z",
      "last_seen": "2026-09-10T12:00:00Z"
    }
  },
  "grants": {
    "hedgedoc2": [
      { "provider": "github", "id": "<verified-numeric-id>", "username": "surma" }
    ]
  },
  "imports": { "seed_apps": { "hedgedoc2": true } },
  "updated_at": "2026-09-10T12:00:00Z",
  "updated_by": "bootstrap"
}
```

User identity is `(provider, id)`. Usernames, emails, and avatars are mutable display data. Roles and grants remain outside JWTs. Every authorization check reads the current committed policy.

Use a mutex for mutations and deep-copy snapshots. Under that mutex, validate the mutation and construct a candidate snapshot. Write a temporary file in the policy directory with mode 0600. Sync the file, atomically rename it, and sync the directory. Publish the candidate in memory only after a successful commit.

Keep the previous committed file as `policy.json.bak` through an atomic backup write. Never back up malformed input over the last good backup. A failed commit must leave the previous committed in-memory policy active.

**Unknown fields:** reject unknown JSON fields at every schema level with `DisallowUnknownFields`. Reject trailing JSON and unsupported versions. Leave the original file untouched. This strict contract replaces the earlier unimplemented promise to preserve arbitrary unknown fields.

**Missing file:** initialize an empty in-memory policy. Commit it only with successful bootstrap and seed import. Failed username resolution must not leave a partially initialized policy.

**Corrupt cold startup:** fail startup without serving restricted access. Do not silently restore `.bak` or overwrite the damaged file. An operator can inspect and restore a known backup with approval.

**Corrupt reload after a good load:** retain the good snapshot for diagnostics. Mark the store unavailable for authorization and mutation. Return 503 until a valid reload or restart succeeds. Do not serve stale grants as a recovery strategy.

**Import marker:** `imports.seed_apps[app] = true` means that app's initial seed import completed. Commit its grants and marker in the same transaction. Mark an empty seed set as imported too. Restart never reimports an app with a marker, even after an admin removes its final grant.

Do not infer import status from a nonempty grant list. Preserve import markers when Nix removes the seed adapter. A username resolution failure leaves the whole initial import uncommitted and blocks readiness.

Retain grants and markers for temporarily absent app keys during rollback or topology changes. Such grants authorize nothing until that exact key exists again. Do not silently garbage-collect runtime data.

Bootstrap admins are Nix-owned exceptions to UI role ownership. Reassert their roles at startup. Label them as managed by Nix in the UI and reject UI demotion. Protect the last runtime admin under the same mutation lock.

### 5.3 Provider and session APIs

Extend `auth.Provider`, not only `GitHubProvider`:

```go
type Provider interface {
    Name() string
    AuthURL(state string) string
    Exchange(code string) (*User, error)
    ResolveUsername(login string) (*User, error)
}

type User struct {
    Provider string
    ID       string
    Username string
    Email    string
    Avatar   string
}
```

GitHub's resolver returns the canonical username and numeric ID. User-entered usernames never become authorization keys. Reject unresolved users without creating a grant.

Inject HTTP clients and endpoint URLs for the user, username lookup, and token exchange. Unit tests use `httptest` only. They must not contact GitHub.

The session constructor accepts the configured cookie name and loaded cookie secret. Its existing signature already includes a cookie name. Update call sites together rather than adding that parameter twice.

JWT claims include `provider`, `uid`, display fields, and registered claims. Set `sub = "<provider>:<uid>"`, issuer `surm-auth`, expiration, and a random session ID in `jti`.

Require HS256 specifically, the expected issuer, expiration, nonempty identity fields, and a matching subject. Reject the old username-only shape. A username rename must preserve grants.

Use `_surm_auth2`, `.surma.technology`, `/`, `Secure`, `HttpOnly`, and `SameSite=Lax`. Default duration is 168 hours. Reuse the existing cookie secret without rotating it during migration.

All users log in again after cutover. Keep the old secret available for rollback. Logout clears the v2 cookie with matching domain and path and `MaxAge = -1`.

Backends still receive the shared cookie through Traefik. They must ignore it. Treat all covered subdomains as part of the existing SSO trust boundary.

### 5.4 Forward-auth and redirects

`GET /auth?app=<key>` follows this matrix:

- Missing, duplicate, or unknown app: 404.
- Internal-only app presented to forward-auth: 403.
- Malformed or cross-app return metadata: 400.
- Required policy state unavailable: 503.
- Public app: 200 without fabricated user identity headers.
- Restricted app without a valid cookie: 302 to canonical `/login`.
- Authenticated app with a valid session: 200 with identity headers.
- Allowlist app with a grant or admin role: 200 with identity headers.
- Allowlist app without a grant: 403 and an audit event.

Public routers bypass forward-auth, so an auth outage does not stop public backends. Unknown app keys never fall back to public behavior.

Login URLs carry the declared app key and a validated return URL. Require HTTPS, exact configured host membership, and the normal HTTPS port. Reject userinfo, protocol-relative URLs, malformed authorities, and external hosts. An invalid user-supplied redirect falls back to the canonical auth landing page.

Do not derive a different policy from a return URL. A direct login link without an app key may resolve a known public domain for display. Callback authorization must use the signed transaction's validated app key.

### 5.5 OAuth transaction contract

Keep GitHub's registered callback exactly `https://auth.surma.technology/callback`.

Canonicalize OAuth initiation to `auth.surma.technology`, including requests that start through the auth alias. This ensures the host-only transaction cookie reaches the fixed callback.

Use an HMAC-signed state payload with these fields:

```go
type StateData struct {
    Provider  string `json:"provider"`
    App       string `json:"app,omitempty"`
    Redirect  string `json:"redirect"`
    Nonce     string `json:"nonce"`
    IssuedAt  int64  `json:"issued_at"`
    ExpiresAt int64  `json:"expires_at"`
}
```

Generate a cryptographically random 32-byte nonce. Set a host-only, secure, HttpOnly, SameSite=Lax transaction cookie on the canonical auth host. Bind its value to the signed transaction. Store outstanding transactions in a bounded in-memory map with a ten-minute expiry.

Verify the signature, provider, timestamps, nonce, browser cookie, and outstanding transaction before exchanging the code. Consume the transaction once under a lock. Delete its cookie. Failed or repeated callbacks require a new login attempt. A restart invalidates pending transactions but not established sessions.

After exchange, upsert display data without changing a role or inventing grants. For app destinations, check that app's current policy before issuing a session.

Auth-host destinations are a separate valid case. An anonymous visit to `/admin` can complete OAuth without an app grant subject. Issue a session for the verified identity, then let `/admin` enforce its current admin role. A non-admin gets 403, not an unknown-app error.

### 5.6 Day-one UI and CSRF

Serve these routes:

- `GET /health`: readiness, including valid policy initialization.
- `GET /login` and `GET /login/github`: login page and OAuth initiation.
- `GET /callback`: the fixed provider callback.
- `GET /`: a safe auth landing page.
- `GET /logout`: a confirmation page only.
- `POST /logout`: clear the session after CSRF validation.
- `GET /admin`: apps, users, roles, and recent audit events.
- `GET /admin/apps/{name}`: Nix-owned topology and editable grants.
- `POST /admin/apps/{name}/grants`: resolve a username and add its stable-ID grant.
- `POST /admin/grants/delete`: remove one grant.
- `POST /admin/users/role`: change one mutable role.
- `GET /admin/audit`: the latest 200 audit events.

Anonymous admin requests redirect to canonical login. Non-admin sessions receive 403 on every admin route. Internal-only and public apps show their explicit mode without grant-edit forms.

Parse templates once during handler construction, matching the existing handlers. Use `html/template` escaping. Constructor errors must stop startup cleanly. Do not parse templates per request.

Retain `login.html` and `error.html`. Add `admin.html`, `admin_app.html`, and `audit.html`. A simple logout confirmation can reuse the constructed template set. No JavaScript or frontend build is required.

Every mutating request requires POST, a valid session, and a CSRF token. Admin mutations additionally require the current admin role.

Sign CSRF tokens with a purpose-separated HMAC using the cookie secret. Bind the token to the session subject, session `jti`, method, action path, and expiry. Use a one-hour lifetime and constant-time signature comparison. Check that the request Origin exactly matches its configured HTTPS auth host.

Reject missing, expired, cross-session, wrong-subject, wrong-action, and forged tokens with 403. Do not accept GET mutations. Test all mutating endpoints, including logout.

### 5.7 Audit behavior

Use `/var/lib/surm-auth/audit.log` as JSON Lines with mode 0600. Record timestamps, actor IDs, subject IDs, app keys, events, and relevant error details.

Events include login success or denial, access denial, grant changes, role changes, logout, seed import, and policy write errors. Read the latest 200 events for the admin UI.

Do not claim a real client IP from `X-Forwarded-For`. Record the trusted peer or leave the field empty. DNAT source NAT prevents client-IP attribution.

Serialize appends. Rotate at 10 MiB into one explicitly managed generation. The audit file is operational data, not an authorization database. Journal write failures without granting access or undoing committed policy changes. Do not log secrets or OAuth codes.

## 6. Nix bootstrap and credential ownership

### 6.1 Auth options and paths

Add these concrete defaults to `modules/services/surm-auth/default.nix`:

- `session.cookieName = "_surm_auth2"`.
- `policy.file = "/var/lib/surm-auth/policy.json"`.
- `audit.file = "/var/lib/surm-auth/audit.log"`.
- `bootstrapAdmins` as stable `{ provider, id }` pairs.
- `apps.<app>.{mode,domains,seedUsers}`.
- Auth-domain aliases for the login and callback validator.

Expose the corresponding surmhosting auth settings. Set `auth.enable = true` on Nexus. Supply concrete `auth.policyFile` and `auth.auditFile` defaults matching the container paths above. Do not leave either path null.

### 6.2 DynamicUser state contract

Keep the auth container at `10.202.0.2`. Separate credentials from writable policy state.

On Nexus, create `/var/lib/surm-auth-state` as root-owned mode 0700. Bind this dedicated directory read-write to `/var/lib/private` inside the auth container. It is the private-state parent for this container only. Do not bind the host's general `/var/lib/private` directory.

Inside the container, configure:

```nix
systemd.services.surm-auth.serviceConfig = {
  DynamicUser = true;
  StateDirectory = "surm-auth";
  StateDirectoryMode = "0700";
  ProtectSystem = "strict";
  PrivateTmp = true;
  ProtectHome = true;
  NoNewPrivileges = true;
  LoadCredential = [
    "github-client-id:/var/lib/secrets/github-client-id"
    "github-client-secret:/var/lib/secrets/github-client-secret"
    "cookie-secret:/var/lib/secrets/cookie-secret"
  ];
};
```

Systemd manages `/var/lib/private/surm-auth` and its `/var/lib/surm-auth` link for the dynamic user. `StateDirectory` supplies the writable sandbox exception. Do not hard-code a transient UID or chown the state to root after initialization.

The concrete host files are:

- `/var/lib/surm-auth-state/surm-auth/policy.json`.
- `/var/lib/surm-auth-state/surm-auth/policy.json.bak`.
- `/var/lib/surm-auth-state/surm-auth/audit.log`.

The container can remain ephemeral because the private-state parent persists through its bind mount. A VM test must prove mutation and persistence across container recreation, not only process restart.

### 6.3 Auth credentials and ordering

Decrypt the three auth credentials to `/var/lib/surm-auth-credentials` on Nexus. The directory is root-owned mode 0700. The files are root-owned mode 0600.

Bind that directory read-only to `/var/lib/secrets` inside the auth container. Container PID 1 reads these root-only source files through `LoadCredential`. The dynamic service reads only `/run/credentials/surm-auth.service/*`.

The generated config must use those runtime credential paths, not the root-only bind-mount paths. Preserve the existing secret values and Pylon recipients during the rollback window.

Order host `secrets.service` after `systemd-tmpfiles-setup.service`. Add `requires` and `after` dependencies on `secrets.service` to the auth container unit. A failed decryption must prevent container startup.

Use explicit restart propagation or an operator restart after credential changes. Ordering alone does not refresh credentials in an already active container or service. Test secret rotation separately from first boot.

### 6.4 Cloudflare and Traefik

Create a dedicated Cloudflare token for the `surma.technology` zone with both permissions:

- `Zone:Zone:Read`.
- `Zone:DNS:Edit`.

Encrypt it as `secrets/surmedge-cloudflare-dns01.age`. Register it inside the existing `secrets` attribute in `secrets/config.nix`. Use recipients `surma` and `nexus`. Do not reuse Scout's token.

Write `/var/lib/surmedge-credentials/cloudflare.env` as root-owned mode 0600. Its contents are `CF_DNS_API_TOKEN=<token>` followed by a newline. Create its parent with mode 0700.

Use the valid NixOS option:

```nix
services.traefik.environmentFiles = [ "/var/lib/surmedge-credentials/cloudflare.env" ];
systemd.services.traefik.requires = [ "secrets.service" ];
systemd.services.traefik.after = [ "secrets.service" ];
services.traefik.staticConfigOptions = {
  certificatesResolvers.cloudflare.acme = {
    email = "surma@surma.dev";
    storage = "/var/lib/traefik/acme.json";
    dnsChallenge.provider = "cloudflare";
  };
  entryPoints = {
    web = {
      address = ":80";
      forwardedHeaders = { insecure = false; trustedIPs = []; };
      http.redirections.entryPoint = { to = "websecure"; scheme = "https"; permanent = true; };
    };
    websecure = {
      address = ":443";
      forwardedHeaders = { insecure = false; trustedIPs = []; };
      http.tls.certResolver = "cloudflare";
    };
    internal.address = ":8081";
  };
};
```

Remove conflicting old forwarded-header definitions rather than merging them into these empty lists. Public application routers use `websecure` only. Port 80 performs the explicit HTTPS redirect.

Let the existing Traefik module own `/var/lib/traefik` and its ACME file. Do not make that directory root-only through the credential installer. Set the module's DNS environment option to the credential path above.

DNS-01 permits certificate issuance without Pylon forwarding to Nexus. It does not make normal DNS requests reach Nexus before cutover. Build time does not issue certificates. Allow time for issuance during the maintenance window unless an operator separately approves preissuance.

### 6.5 LLM credentials and state

Create `machines/nexus/service-llm-proxy.nix` from the existing Pylon service topology. Resolve secrets on Nexus before enabling its container.

Keep one declaration per secret on Nexus. The secrets module gives `command` precedence over `target`. A second target does not create a second decrypted copy.

Use these explicit consumer contracts:

- `llm-proxy-secret`: replace its target declaration in `machines/nexus/default.nix` with one command. Read stdin once. Write `/var/lib/key-poller/receiver-secret` as root-owned mode 0400. Also write `/var/lib/llm-proxy-credentials/receiver-secret` as root-owned mode 0644.
- `llm-proxy-client-key`: extend its existing command in `machines/nexus/service-scout.nix`. Read stdin once. Write both `/var/lib/scout/llm-proxy-client-key` and `/var/lib/llm-proxy-credentials/client-key` as root-owned mode 0644.
- `openrouter-api-key`: extend its existing command in `machines/nexus/service-scout.nix`. Read stdin once. Preserve `/var/lib/scout/openrouter-api-key` as `surma:users`, mode 0600. Also write `/var/lib/llm-proxy-credentials/openrouter-key` as root-owned mode 0644.

Declare no competing targets. Each command writes all its destinations explicitly. Create `/var/lib/llm-proxy-credentials` with mode 0755. Bind it read-only to `/var/lib/credentials` inside the LLM container.

This preserves each consumer's existing ownership and file modes. Do not bind the poller's root-only 0400 file directly into the unprivileged LLM receiver. The receiver needs its own readable copy.

Require `secrets.service` before the LLM container and key poller start. Restart affected consumers after credential replacement. Verify all six file reads across the poller, receiver, LLM services, and Scout.

Preserve the key poller's receiver URL and Brain's current LLM endpoint. Their existing public domain aliases follow the service move. Do not use an OpenRouter model for verification without separate approval.

Copy only mutable LLM state from `/var/lib/llm-proxy` during the maintenance window. Regenerate credentials from Nexus's declarations. Do not rely on a copied credential directory to hide missing secret commands.

Stop the old receiver and pause its poller before the final state copy. Preserve the Pylon copy. Verify ownership and checksums before Nexus starts the receiver. Do not delete source state.

Stop both `key-poller.timer` and `key-poller.service` during the cutover and rollback windows. Verify their stopped state after each generation switch before any state reconciliation. Resume the timer only at the explicit resume step.

## 7. Internal HTTP consumers and source inventory

Update every Nexus internal HTTP authority to include `:8081`. Preserve the hostname and any path suffix. Do not change SSH hosts, listener ports, or unrelated direct backend URLs.

### 7.1 Existing files that require HTTP changes

- `machines/nexus/service-firefly.nix`: `APP_URL`.
- `machines/nexus/service-firefly-importer.nix`: script and service values for `FIREFLY_III_URL` and `VANITY_URL`.
- `machines/nexus/service-firefly-enricher.nix`: exported `FIREFLY_URL`.
- `machines/nexus/service-firefly-categoriser.nix`: exported `FIREFLY_URL`.
- `machines/nexus/firefly-enricher/enricher.py`: fallback URL.
- `machines/nexus/firefly-categoriser/categoriser.py`: fallback URL.
- `machines/nexus/service-gitea-runner.nix`: runner HTTP URL.
- `machines/nexus/service-rss.nix`: FreshRSS base URL.
- `modules/programs/gitea-cli/default.nix`: HTTP default, not `ssh_host`.
- `assets/skills/hedgedoc/SKILL.md`: HedgeDoc API base URL.
- `assets/skills/music/SKILL.md`: Navidrome, Lidarr, Prowlarr, and qBittorrent base URLs and examples.
- `assets/skills/nexus-admin/SKILL.md`: Nexus base URL and all Nexus examples. Keep Citadel examples unchanged.
- `machines/scout/AGENTS.md`: Nexus admin URL in the source overlay.

Do not edit generated AGENTS files. Install the updated source skills and Gitea CLI configuration on their actual consumers during the maintenance window. Updating repository text alone does not update existing Scout sessions or Home Manager profiles.

Record consumers outside the two host generations before cutover. Reapply their approved Home Manager configurations or provide explicit temporary `:8081` overrides. Restart sessions that retain old instructions. Their rollback must restore the old HTTP defaults after Nexus returns to port 80.

### 7.2 Other routes and URLs to classify

Pylon's proxy files intentionally retain old port-80 URLs in the old generation. The new Pylon generation removes their imports. Do not rewrite those old URLs as a false compatibility stage.

Set the Jellyfin and Jaeger Docker router labels to `entrypoints=internal`. Preserve their internal host rules. Their direct media and telemetry ports do not change.

Preserve the direct Dump endpoint in `machines/dragoon/home.nix`: `http://10.0.0.2:8123`. It does not traverse the moved Traefik entrypoint.

Preserve loopback Syncthing API URLs and Firefly virtualHost names without port text. Append the port to HTTP authorities, not to bare host configuration fields.

Remove Pylon's tracing import when Traefik leaves Pylon. Its direct OTLP endpoint does not require conversion to 8081.

Search the whole repository, excluding the two planning documents, before implementation completes:

```bash
rg -n 'https?://[^"[:space:]<>`]*nexus\.hosts\.' . --glob '!auth-rework*.md'
rg -n 'nexus\.hosts|surmcluster|100\.83\.198\.90|10\.0\.0\.2' machines modules assets profiles apps packages --glob '!*.age'
```

Classify every result. The first command includes valid new URLs, so nonempty output is expected. This is not an assertion that every `nip.io` string needs a port.

Use a URL-aware check for stale HTTP defaults. It must ignore unimported legacy Pylon proxy files and inspect parsed URL ports. Do not use the previous invalid negative-lookahead command.

## 8. Pylon forwarding and UDP behavior

### 8.1 Forwarding configuration

Use the pinned nftables NAT module. Capture the actual public IPv4 and verify the current Tailscale destinations before implementation.

```nix
let
  nexusTsV4 = "100.83.198.90";
  citadelTsV4 = "100.70.63.93";
  pylonPublicV4 = "<verified-pylon-public-ipv4>";
in {
  networking.nftables.enable = true;
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp1s0";
  networking.nat.forwardPorts = [
    { sourcePort = 80; destination = "${nexusTsV4}:80"; proto = "tcp"; loopbackIPs = [ pylonPublicV4 ]; }
    { sourcePort = 80; destination = "${nexusTsV4}:80"; proto = "udp"; loopbackIPs = [ pylonPublicV4 ]; }
    { sourcePort = 443; destination = "${nexusTsV4}:443"; proto = "tcp"; loopbackIPs = [ pylonPublicV4 ]; }
    { sourcePort = 443; destination = "${nexusTsV4}:443"; proto = "udp"; loopbackIPs = [ pylonPublicV4 ]; }
    { sourcePort = 2222; destination = "${nexusTsV4}:2222"; proto = "tcp"; loopbackIPs = [ pylonPublicV4 ]; }
    { sourcePort = 25565; destination = "${citadelTsV4}:25565"; proto = "tcp"; loopbackIPs = [ pylonPublicV4 ]; }
  ];
  networking.nftables.tables.surmedge-forward = {
    family = "ip";
    content = ''
      chain post {
        type nat hook postrouting priority srcnat; policy accept;
        ct status dnat oifname "tailscale0" ip daddr ${nexusTsV4} tcp dport { 80, 443, 2222 } masquerade
        ct status dnat oifname "tailscale0" ip daddr ${nexusTsV4} udp dport { 80, 443 } masquerade
        ct status dnat oifname "tailscale0" ip daddr ${citadelTsV4} tcp dport 25565 masquerade
      }
    '';
  };
}
```

The six forwards cover both web protocols plus Gitea SSH and Minecraft. Source NAT covers Nexus and Citadel destinations. It avoids broad masquerade of unrelated tailnet traffic.

The NAT module scopes external DNAT to `enp1s0`. `loopbackIPs` covers hairpin and Pylon-originated access to the public IPv4. The custom source NAT gives externally originated Minecraft traffic a return path through Pylon.

Inspect the complete generated ruleset and active firewall before deployment. Do not assume a forward chain is absent. Preserve container forwarding and the pinned firewall's DNAT acceptance. Do not enable restrictive forwarding rules without equivalent explicit accepts.

### 8.2 Nexus UDP contract

Day one forwards UDP 80 and UDP 443 to Nexus, but Nexus runs no UDP web listener. Do not enable Traefik `http3` and do not advertise `Alt-Svc: h3`.

Nexus permits public TCP 80/443. Its firewall leaves UDP 80/443 closed. UDP packets reach Nexus's Tailscale interface and stop there. UDP forwarding is a transport provision, not a claim of HTTP/3 service.

Verify both UDP ports with packet capture and unique test payloads. Capture before Nexus's input filter. A timeout from a UDP client is not evidence that forwarding works.

### 8.3 Pylon services after cutover

Remove Pylon's surmhosting, surm-auth, LLM, HTTP proxy, and Traefik tracing imports in the new generation. Replace the Gitea SSH and Minecraft Traefik routers with the NAT entries above.

Remove only the surmhosting exposure block from `machines/pylon/service-nixos-admin.nix`. Leave its listener bound to `127.0.0.1:8092`. Task 4 adds the missing import to activate that listener in the new generation. Do not assume this unit exists before that import. Keep OpenSSH and the Syncthing relay on TCP 22067.

Keep `machines/pylon/ports.nix`, hardware, and Home Manager configuration. Do not remove old credential or state directories. Retain old generations and source files for rollback. Source-file cleanup can occur later with separate approval.

## 9. Implementation tasks and verification gates

Each task starts with failing tests or an explicit evaluation fixture. Implement the smallest change that satisfies them. These are planned checks, not results already obtained.

### Task 0 — Operator preparation, without deployment

**Existing files:** `secrets/config.nix`, `machines/pylon/default.nix`, and `machines/nexus/default.nix` provide the current values and recipients.

**New secret:** `secrets/surmedge-cloudflare-dns01.age`.

1. Record immutable old Nexus and Pylon generation paths and their source revisions.
2. Record the reviewed new revision before deployment approval.
3. Verify Pylon's public IPv4, Nexus's Tailscale IPv4, and Citadel's Tailscale IPv4.
4. Inventory A and AAAA records for every legacy domain and alias.
5. Verify the GitHub callback and Surma's numeric ID.
6. Obtain approval for DNS and credential changes.
7. Add `apps.surma.technology` A and `*.apps.surma.technology` CNAME records, DNS-only.
8. Leave existing DNS records unchanged unless an explicit IPv6 decision requires a change.
9. Add Nexus recipients to the three existing auth secrets without removing Pylon.
10. Verify Nexus recipients for the three LLM secrets.
11. Create the dedicated Cloudflare token with both required permissions.
12. Record state backup locations and the final LLM copy procedure.

Commands from the repository root:

```bash
curl -fsS https://api.github.com/users/surma
nix run .#secrets -- recrypt surm-auth-github-client-id surm-auth-github-client-secret surm-auth-cookie-secret
nix run .#secrets -- recrypt surmedge-cloudflare-dns01
dig +short apps.surma.technology A
dig +short hedgedoc.apps.surma.technology A
```

Inspect the GitHub response's numeric `id`. Verify decryption without printing secret values. Token creation and encryption precede `recrypt`. Any missing recipient, AAAA decision, or rollback artifact blocks cutover.

### Task 1 — Coupled Go model and policy work

**Modify:** `apps/surm-auth/config/config.go`, `apps/surm-auth/auth/provider.go`, `apps/surm-auth/auth/github.go`, `apps/surm-auth/auth/session.go`, and `apps/surm-auth/auth/state.go`.

**Create:** `apps/surm-auth/policy/policy.go`, `apps/surm-auth/policy/policy_test.go`, `apps/surm-auth/audit/audit.go`, and `apps/surm-auth/audit/audit_test.go`.

**Create tests:** `apps/surm-auth/config/config_test.go`, `apps/surm-auth/auth/github_test.go`, `apps/surm-auth/auth/session_test.go`, and `apps/surm-auth/auth/state_test.go`.

1. Define the v2 config and provider interfaces before dependent handlers.
2. Test secret loading, strict config validation, and rejected v1 YAML.
3. Test provider exchange and username resolution with injected local endpoints.
4. Test the session claims and OAuth transaction contract.
5. Test atomic policy writes, backups, and failed-commit memory behavior.
6. Test missing state, cold corruption, corrupt reload, and unknown fields.
7. Test seed markers after final-grant removal and restart.
8. Test concurrent last-admin changes and pinned bootstrap roles.
9. Test audit writes, bounded reads, and failure behavior.

Treat Tasks 1 and 2 as one coupled Go integration batch. Compile affected packages as APIs become available. Do not claim every intermediate commit builds the unchanged v1 main program. The release gate requires the complete batch.

### Task 2 — Handlers, UI, bootstrap, and package

**Modify:** `apps/surm-auth/handlers/auth.go`, `apps/surm-auth/handlers/login.go`, `apps/surm-auth/handlers/callback.go`, `apps/surm-auth/handlers/logout.go`, and `apps/surm-auth/main.go`.

**Modify:** `apps/surm-auth/templates/login.html` and `apps/surm-auth/templates/error.html` as required for the new flow.

**Create:** `apps/surm-auth/handlers/admin.go`, `apps/surm-auth/handlers/handlers_test.go`, `apps/surm-auth/handlers/auth_test.go`, `apps/surm-auth/handlers/login_test.go`, `apps/surm-auth/handlers/callback_test.go`, and `apps/surm-auth/handlers/admin_test.go`.

**Create:** `apps/surm-auth/templates/admin.html`, `apps/surm-auth/templates/admin_app.html`, `apps/surm-auth/templates/audit.html`, and `apps/surm-auth/main_test.go`.

Use this startup order:

1. Load and validate the v2 config.
2. Load all secrets.
3. Construct providers and their resolvers.
4. Open policy and audit state.
5. Resolve only the apps without completed seed markers.
6. Commit bootstrap admins, initial grants, and import markers atomically.
7. Construct session management, transaction state, handlers, and templates.
8. Start HTTP and report readiness.

Audit seed imports only after their commit succeeds. A provider failure before commit must not create partial grants or markers.

Test the complete forward-auth matrix. Test both auth-host login paths, malformed redirects, nonce expiry, cookie binding, replay, and admin POST CSRF. Test current-policy revocation without a new session cookie.

Use an explicit template path in handler tests. Package-relative working directories must not determine template lookup.

Add `TestPackagedServer` in `main_test.go`. When `SURM_AUTH_BIN` is set, start that binary with valid temporary config and synthetic secrets. Verify health, login rendering, admin rendering with a test-signed admin cookie, and a persisted grant mutation. Start the process outside the source tree. Stop it through test cleanup.

The package already copies the whole templates directory and sets `SURM_AUTH_TEMPLATES`. Inspect `packages/surm-auth/default.nix`. Change it only if packaging or dependencies actually require a change. Do not add a filename list or change `vendorHash` without a dependency change.

From `apps/surm-auth`, using the repository's pinned toolchain:

```bash
nix shell --impure --expr '(builtins.getFlake (toString ../..)).inputs.nixpkgs.legacyPackages.x86_64-linux.go' -c go vet ./...
nix shell --impure --expr '(builtins.getFlake (toString ../..)).inputs.nixpkgs.legacyPackages.x86_64-linux.go' -c go test -race ./...
nix shell --impure --expr '(builtins.getFlake (toString ../..)).inputs.nixpkgs.legacyPackages.x86_64-linux.go' -c gofmt -l .
```

Expected: zero exit status for vet and tests. `gofmt -l` must print no paths. Do not interpret its exit status alone as a formatting check.

From the repository root, after adding new source files to the implementation branch:

```bash
nix build --no-link .#packages.x86_64-linux.surm-auth
SURM_AUTH_BIN="$(nix eval --raw .#packages.x86_64-linux.surm-auth.outPath)/bin/surm-auth"
export SURM_AUTH_BIN
```

Then rerun `go test -run '^TestPackagedServer$' -count=1 .` from `apps/surm-auth` with the pinned Go shell above. Require the test to run, not skip. A `/dev/null` config failure is not a package smoke test.

### Task 3 — Modules and complete Nexus declarations

**Modify:** `modules/services/surmhosting/default.nix` and `modules/services/surm-auth/default.nix`.

**Modify:** `machines/nexus/default.nix` and all current exposure files listed below.

**Create:** `machines/nexus/service-surm-auth.nix`, `machines/nexus/service-ha-proxy.nix`, and `machines/nexus/service-llm-proxy.nix`.

Public declarations belong in these existing files:

- `machines/nexus/service-hedgedoc2.nix`.
- `machines/nexus/service-gitea.nix`.
- `machines/nexus/service-dump.nix`.
- `machines/nexus/service-brain-serve.nix`.
- `machines/nexus/service-scout-static.nix`.
- `machines/nexus/service-music.nix`.
- `machines/nexus/service-jazzy-poisonous-plant-parlour.nix`.

Internal declarations belong in these existing files:

- `machines/nexus/service-nexus-admin.nix`.
- `machines/nexus/service-copyparty.nix`.
- `machines/nexus/service-firefly.nix`.
- `machines/nexus/service-firefly-importer.nix`.
- `machines/nexus/service-lidarr.nix`.
- `machines/nexus/service-prowlarr.nix`.
- `machines/nexus/service-radarr.nix`.
- `machines/nexus/service-sonarr.nix`.
- `machines/nexus/service-overview.nix`.
- `machines/nexus/service-rss.nix`.
- `machines/nexus/service-syncthing.nix`.
- `machines/nexus/service-torrent.nix`.
- `machines/nexus/service-voice-memos.nix`.

Also modify Docker labels in `machines/nexus/service-jellyfin.nix` and `machines/nexus/service-jaeger.nix`.

1. Implement the schema, assertions, middleware keys, and explicit auth enablement.
2. Render the v2 config and dynamic service contract.
3. Add DNS-01, explicit redirects, and public header distrust.
4. Declare the complete initial inventory from Section 4.
5. Implement credentials and dependency ordering from Section 6.
6. Extend the existing LLM secret commands in `machines/nexus/service-scout.nix`.
7. Update every internal HTTP consumer in Section 7.
8. Preserve container identity and state mounts during the refactor.

Adding the LLM service can change index-derived container IPs in the existing module. Compare the complete old and new evaluated address maps. Preserve container names and regenerate all backend URLs together. Inventory any fixed-address callers before accepting the change.

### Task 4 — Pylon configuration and migration tests

**Modify:**

- `machines/pylon/default.nix`: replace the edge imports and add the missing `./service-nixos-admin.nix` import.
- `machines/pylon/service-gitea-ssh.nix` and `machines/pylon/service-minecraft-proxy.nix`: replace their Traefik routers with the planned NAT rules.
- `machines/pylon/service-nixos-admin.nix`: remove only its surmhosting exposure block. Preserve the localhost listener and other service configuration.

1. Remove the imports described in Section 8.3.
2. Remove only `services.surmhosting.services.admin` from `machines/pylon/service-nixos-admin.nix`.
3. To provide the planned Pylon localhost admin listener, add `./service-nixos-admin.nix` to `machines/pylon/default.nix` imports.
4. Apply the import and exposure removal in the same generation. Leave `listenAddress = "127.0.0.1:8092"` unchanged.
5. Verify the enabled admin service and generated unit after the import. Before that change, do not assume either exists.

Keep the old proxy source files unimported during the rollback window. Confirm `services.traefik.enable = false` in the new Pylon configuration.

**Create:** `modules/services/surmhosting/tests.nix`.

This test file accepts `{ pkgs, inputs }` and returns `migration` and `authBootstrap` derivations. Use `pkgs.testers.runNixOSTest` for both. Import the real service modules into fixtures rather than reproducing their new router logic in tests.

The migration fixture must cover:

- The complete evaluated logical app inventory and all public aliases.
- Brain's split policies, all LLM ports, and HedgeDoc's shared app.
- No implicit public route for any internal-only service.
- Docker routers and the dashboard restricted to the internal entrypoint.
- Missing-policy and conflicting-domain assertions.
- Auth remains enabled after removal of the seed adapter.
- Spoofed forwarded headers through actual generated Traefik middleware.
- TCP and UDP web DNAT entries with source NAT.
- Nexus and Citadel external return paths, plus hairpin paths.
- Old-old and new-new topology success.
- Expected old-Pylon/new-Nexus failure during the forward transition.
- Expected new-Pylon/old-Nexus failure during the rollback transition.
- Final restoration of the old topology after the documented rollback order.

Use isolated legacy routing fixtures captured from the current configuration for the old topology. Do not claim the new module can render a compatible v1 deployment. The live rollback drill still uses the saved old generations.

The bootstrap fixture must use the real DynamicUser service and bind mounts. Start with empty state and synthetic secrets. Verify credential reads, grant writes, container recreation, and persistence. Verify failed decryption prevents startup. Test each LLM consumer path after fresh decryption and after secret replacement.

Mock remote provider endpoints in tests. Do not contact GitHub, Cloudflare, or OpenRouter from these fixtures.

From the repository root:

```bash
nix eval --raw .#nixosConfigurations.nexus.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.pylon.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.citadel.config.system.build.toplevel.drvPath
nix eval --json .#nixosConfigurations.nexus.config.containers.surm-auth.config.services.surm-auth
nix eval --json .#nixosConfigurations.nexus.config.services.traefik.dynamicConfigOptions
nix eval --json .#nixosConfigurations.pylon.config.networking.nat.forwardPorts
nix eval --json .#nixosConfigurations.pylon.config.services.traefik.enable
# These admin checks require the new Task 4 import.
nix eval --json .#nixosConfigurations.pylon.config.services.nixos-admin.enable
nix eval --json .#nixosConfigurations.pylon.config.services.nixos-admin.listenAddress
nix eval --raw '.#nixosConfigurations.pylon.config.systemd.units."nixos-admin.service".text'
nix flake check --no-build
nix build --no-link .#nixosConfigurations.nexus.config.system.build.toplevel .#nixosConfigurations.pylon.config.system.build.toplevel
nix build --no-link --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in (import ./modules/services/surmhosting/tests.nix { inherit pkgs; inputs = f.inputs // { self = f; }; }).migration'
nix build --no-link --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in (import ./modules/services/surmhosting/tests.nix { inherit pkgs; inputs = f.inputs // { self = f; }; }).authBootstrap'
```

Expected: every command exits zero after Task 4, including the missing import. The Pylon Traefik value is exactly `false`. The admin enable value is `true`, and its listen address is `"127.0.0.1:8092"`. The rendered `nixos-admin.service` unit must exist. The NAT list has the six declared entries. Inspect unit definitions and generated configuration, not only shallow option values.

An attribute error is a failure, not an acceptable alternative result. The auth module lives inside the container configuration, not host `services.surm-auth`. Register new files with Git before flake builds, because a Git flake omits untracked implementation files.

### Task 5 — Coordinated maintenance cutover

Build both new closures and pass all preceding gates before requesting deployment approval. Confirm the exact immutable revision and both target hosts. Capture rollback paths outside the HTTP route that will change.

Use SSH or Citadel's unchanged admin route as the control path. If the admin API deploys remotely, specify `target_host`. Never send a different host's flake fragment to a local deploy endpoint without it.

**Exact forward order:**

1. Announce the maintenance outage and pause writes to the LLM receiver.
2. Pause the Nexus key poller and stop the old Pylon LLM receiver.
3. Complete the approved final state copy to Nexus.
4. Deploy the approved new Nexus generation first.
5. Verify its credentials, policy initialization, certificates, and direct HTTPS routes.
6. Deploy the approved new Pylon generation second.
7. Restore the key poller and verify its receiver through the legacy alias.
8. Apply the approved external HTTP consumer updates or explicit overrides.
9. Complete the public, internal, OAuth, SSH, and Minecraft matrix.
10. End maintenance only after the required checks pass.

Step 4 breaks old Pylon's HTTP backend routes until Step 6. This is the approved outage, not a supported mixed-generation state. If either deploy fails, stop and report its status and full logs. Request approval for the rollback sequence in Section 11.

Before Step 6, direct checks must override DNS:

```bash
NEXUS_TS=100.83.198.90
curl --fail-with-body --show-error --resolve "auth.surma.technology:443:$NEXUS_TS" https://auth.surma.technology/health
curl --show-error --silent --output /dev/null --write-out '%{http_code} %{redirect_url}\n' --resolve "hedgedoc.apps.surma.technology:443:$NEXUS_TS" https://hedgedoc.apps.surma.technology/
```

Use normal certificate verification. Do not add `-k`. The auth health request must return 200. The anonymous HedgeDoc request must return 302 to canonical login.

A pre-cutover browser OAuth test requires local overrides for both auth hosts and the selected app host. The fixed callback host must reach Nexus too. Otherwise, defer the full browser round trip until after Step 6. Normal DNS still reaches old Pylon before that step.

Use `http://admin.nexus.hosts.100.83.198.90.nip.io:8081/api/health` from a tailnet client. A LAN client can use the `10.0.0.2` variant. Do not assume every tailnet client routes the Nexus LAN address.

### Task 6 — Post-cutover verification and seed cleanup

Verify the initial grants and their import markers in the admin UI and persistent state. Then remove the `allowedGitHubUsers` adapter and redundant seed declarations in a separate change.

Preserve explicit access modes, app keys, aliases, and `auth.enable`. Preserve import markers even if all seed declarations disappear. Repeat tests and the live matrix after the separately approved Nexus deployment.

Do not change canonical backend URLs, unrelated domains, client-IP architecture, or access policies during this cleanup. Keep old generations and data until the user closes the rollback window.

## 10. Acceptance matrix

Run public checks from an external network without tailnet access. Run internal checks separately from LAN, tailnet, and containers. Check backend identity as well as status codes for multi-port services.

### 10.1 Automated Go and integration tests

- Complete policy decision matrix, including missing and duplicate app keys.
- Strict config and policy parsing, unknown fields, and unsupported versions.
- Stable-ID grants survive username changes.
- Failed writes never publish uncommitted grants.
- Seed markers survive removal of all grants and repeated restarts.
- DynamicUser can read credentials and persist policy across container recreation.
- Mocked OAuth exchange, expiry, browser binding, replay rejection, and auth-host login.
- All admin mutations reject absent, forged, expired, cross-session, and wrong-action CSRF tokens.
- Anonymous admin navigation completes login and returns to `/admin`.
- Non-admin auth-host login succeeds, but admin access returns 403.
- Packaged templates render outside the source tree.
- Old-old and new-new topologies pass. Mixed states fail as documented.

### 10.2 Public HTTP and policy checks

1. `public-brain`, `jazzy`, and `music` reach their expected backends on primary and legacy domains.
2. All five allowlisted apps redirect anonymous clients to canonical login on both namespaces.
3. Surma's bootstrap admin session reaches every restricted app and the day-one UI.
4. Add a grant for user B on Gitea. B reaches Gitea but not private Brain.
5. Remove B's Gitea grant. B receives 403 without a new login.
6. A public Brain request reaches port 8081. Private Brain still requires its separate grant.
7. HedgeDoc frontend, API, uploads, and realtime traffic use the same `hedgedoc2` policy.
8. Each LLM alias reaches its matching port, not either sibling port.
9. LLM client authentication and key receiver authentication still reject invalid credentials.
10. Home Assistant retains its application login behavior and backend destination.
11. HTTP port 80 redirects to HTTPS. Certificates validate without insecure flags.
12. Auth outage leaves public backends available and restricted backends closed.

**Spoofed-header acceptance test:** Send these requests through the deployed Pylon public edge, without a session:

```bash
curl --silent --show-error --dump-header - --output /dev/null \
  -H 'X-Forwarded-Host: public-brain.apps.surma.technology' \
  -H 'X-Forwarded-Proto: https' \
  -H 'X-Forwarded-Uri: /' \
  https://hedgedoc.apps.surma.technology/
curl --silent --show-error --dump-header - --output /dev/null \
  -H 'X-Forwarded-Host: public-brain.surma.technology' \
  'https://hedgedoc.surma.technology/?app=public-brain'
```

Both must enforce `hedgedoc2` and redirect to login. Neither may return HedgeDoc content. Repeat with user B's session and `X-Forwarded-Host: gitea.apps.surma.technology`. B's Gitea grant must not authorize HedgeDoc. Repeat after removal of the legacy seed adapter.

**Internal-host attack test:** Set `PIPV4` to Pylon's verified public IPv4:

```bash
curl --silent --show-error --dump-header - --output /dev/null \
  -H 'Host: rss.nexus.hosts.10.0.0.2.nip.io' "http://$PIPV4/"
curl --silent --show-error --dump-header - --output /dev/null \
  -H 'Host: rss.nexus.hosts.10.0.0.2.nip.io' \
  --resolve "auth.surma.technology:443:$PIPV4" https://auth.surma.technology/
```

The HTTP request may redirect or return 404. It must not serve RSS. The HTTPS request must not match an internal router. Repeat against dashboard, Jellyfin, and Jaeger hosts. Test Pylon public port 8081 separately for refusal or timeout.

A public request to a Tailscale-only IP is not sufficient evidence for this boundary.

### 10.3 Internal callers and non-web services

- Gitea runner and Gitea CLI use Nexus port 8081 successfully.
- Firefly importer, enricher, and categorizer use their new HTTP URLs.
- FreshRSS retains internal access without a new public route.
- Scout's HedgeDoc, music, and Nexus admin clients use updated URLs.
- Jellyfin, Jaeger, overview, and the dashboard remain reachable internally only.
- The direct Dump endpoint and loopback Syncthing calls remain unchanged.
- Public and hairpin Gitea SSH connections return the expected server identity on port 2222.
- Public and hairpin Minecraft connections complete a protocol handshake on port 25565 through Citadel.
- A real Minecraft client can join the existing server after cutover.
- The Syncthing relay remains reachable on TCP 22067.
- After Task 4's import and deployment, Pylon's `nixos-admin.service` is active and reachable through its SSH tunnel. Its listener binds only to `127.0.0.1:8092`.

A TCP connect alone does not prove Minecraft service preservation. Verify the game protocol and the expected server.

### 10.4 UDP checks

Start this capture on Nexus before the external sender:

```bash
sudo tcpdump -ni tailscale0 -s 0 -X -c 2 'udp and (dst port 80 or dst port 443)'
```

From an external client, set `PIPV4` to the verified address and send both test datagrams:

```bash
python3 - "$PIPV4" <<'PY'
import secrets
import socket
import sys
nonce = secrets.token_hex(8)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    for port in (80, 443):
        payload = f"surmedge-{port}-{nonce}".encode()
        print(payload.decode(), flush=True)
        sock.sendto(payload, (sys.argv[1], port))
PY
```

Match the two test payloads and verify the source is Pylon's tailnet address. Repeat from a hairpin client. Inspect the NAT entries independently. Verify Nexus exposes no UDP web listener and advertises no HTTP/3 alternative.

The expected application outcome is no UDP web response. Packet arrival, not response success, proves the required forwarding.

## 11. Rollback playbook

Rollback preserves access control. Never recover by setting restricted apps to `public`.

Keep old and new immutable generation references for both hosts. Keep auth and LLM secrets with all required recipients. Keep Pylon's old mutable state and Nexus's new policy state. Do not delete either copy during rollback.

**Exact rollback order after full cutover:**

1. Announce maintenance and pause the key poller and new LLM receiver.
2. Preserve the current Nexus policy, audit, and LLM state before any replacement.
3. Restore the approved old Nexus generation first.
4. Verify internal HTTP port 80 and old backend routes directly.
5. Reconcile any new LLM receiver state with the preserved Pylon copy under explicit approval.
6. Restore the approved old Pylon generation second.
7. Restore external HTTP clients to their old port-80 defaults.
8. Resume the old receiver and key poller.
9. Verify legacy domains, old OAuth login, Gitea SSH, Minecraft, and internal callers.

New Pylon with old Nexus is an expected outage between Steps 3 and 6. Old Pylon works only after old Nexus restores its port-80 routes. A Pylon-only rollback does not restore legacy service access.

If the Nexus deploy fails before Pylon changes, restore old Nexus and leave old Pylon active. If Pylon deploy fails after Nexus changes, apply the coordinated rollback order. Inspect any automatic rollback status before deciding which host still needs restoration.

Legacy DNS remains unchanged. The new apps names may be unavailable after full rollback because the old generation does not serve them. State this limitation to users. Do not remove their DNS records without approval.

V2 cookies do not authenticate v1. Users may need another login after rollback. Preserve the cookie secret and callback registration. Do not rotate credentials as part of rollback.

For a bad grant, use the admin UI rather than a host rollback. For a corrupt policy, stop auth and preserve the damaged file before an approved backup restore. Restart only after validation succeeds. Do not overwrite runtime state through a configuration deploy.

For a certificate problem, fix the dedicated token or credential file and restart Traefik with approval. Preserve its ACME state ownership. An existing certificate can continue to work while renewal fails, but it is not a permanent recovery path.

## 12. Completion and residual risks

The migration is complete only after both new generations and all required acceptance checks succeed. Report the exact deployed revisions and remaining failures. Keep rollback artifacts until the user explicitly closes the window.

Accepted limitations:

- Public client IPs collapse to Pylon's Tailscale address.
- LAN and tailnet clients retain unauthenticated internal HTTP access.
- Pending OAuth transactions do not survive an auth process restart.
- Nexus becomes the dependency for public TLS and authentication.
- UDP web forwarding exists without an HTTP/3 service.
- Unrelated secondary domains need a separate session design.

Nexus downtime now also affects authentication and LLM services that previously ran on Pylon. Do not claim the outage impact is unchanged.

Before implementation, resolve any live AAAA records, fixed container-IP consumers, and unlisted installed HTTP clients. Those inventory items are deployment gates, not reasons to weaken policy.
