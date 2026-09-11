# Review of the dynamic access plan

**Status: BLOCKED**

The plan needs revision before implementation or deployment. Five ranked findings cover the release blockers below. Each finding groups failures in one implementation workstream.

The broad architecture fits the request. The proposed configuration does not yet preserve access policy, service startup, or the migration path.

## Review basis

- Repository: `/home/containeruser/.local/state/scout/topics/8504/nixenv-hedgedoc2`.
- Branch: `scout/dynamic-service-access`.
- Commit: `9345a14cf8f4cc8bd360bf475e7f558134b20c9f`.
- Git reported the branch three commits behind its local `origin/main` reference. I did not fetch or change branches.
- I read all 1,351 lines of `auth-rework.md`.
- Plan SHA-256: `e3d3056ded5c827834700d71d6153073807527583643ce4639c2ef249dbaf8a3`.
- The alternate directory `nixenv-hedoc2` does not exist. This report uses the requested fallback directory.
- The plan was the only source-tree change before this review.

The requirement authority is the delegated review request. I did not assume requirements from an earlier conversation.

The repository instruction authority is `assets/AGENTS.md`, particularly the rules on surgical changes and executable verification. The review request overrides the normal implementation workflow. I did not deploy, change DNS, commit, push, install tools, or edit implementation files.

### Pinned dependencies

The root flake follows `nixpkgs_6`, not the lock node named `nixpkgs`.

- `flake.nix:3`: `nixos-26.05`.
- `flake.lock`, `nodes.root.inputs.nixpkgs`: `nixpkgs_6`.
- `flake.lock`, `nodes.nixpkgs_6.locked.rev`: `5dfba6236110080a54247d6460bc2ff5dda939cc`.
- Resolved source: `/nix/store/6bf80a7m11xpxdh0qi5k83721lqxk11s-source`.
- Evaluated Traefik version: `3.7.10`.
- Evaluated Go version: `1.26.6`.
- `apps/surm-auth/go.mod:3-9`: Go language version `1.21`, JWT `v5.2.0`, OAuth2 `v0.15.0`, YAML `v3.0.1`.

Below, **nixpkgs/** means a path relative to that exact resolved source. External source references identify a version and a function when line numbers are unavailable.

## Requirement coverage

- **Day-one admin UI:** The plan includes the required pages and mutations. Startup and callback verification remain incomplete. See findings 3 and 4.
- **Apps namespace:** The plan uses `*.apps.surma.technology`. Its implicit publication rule includes services outside its migration table. See finding 2.
- **Nexus HTTPS:** The architecture meets the requirement. The environment option and DNS token scope prevent the documented bootstrap. See finding 4.
- **Pylon TCP/UDP forwarding:** The plan selects packet forwarding, but its rules implement TCP only. See finding 5.
- **Dynamic per-service policy:** Runtime grants and stable provider IDs fit the requirement. The routing model cannot represent all existing services. See findings 1 and 2.
- **One person, one service:** The proposed grant tuple fits. Brain needs two logical policy subjects despite its single container. See finding 2.
- **GitHub-first provider abstraction:** The existing interface provides a suitable base. The plan must define username resolution through that abstraction.
- **Secondary domains:** Aliases within `surma.technology` fit the cookie scope. The plan does not provide SSO for unrelated registrable domains.
- **Shell alias-forwarding:** Sections 1.2 and 6 explicitly preserve it. `profiles/home-manager/base.nix:13-14,164-170` contains the relevant SSH behavior. No change is necessary there.

## Ranked blockers

### 1. Critical — DNAT makes the proposed trusted forwarded host client-controlled

**Requirement:** Dynamic policy must protect each restricted service. Section 3.3 explicitly requires every public path to enforce that service's policy.

**Plan locations:** Section 3.3, lines 103-107. Section 4.9, lines 379-380. Task 1.6, lines 737-739. Task 3.1, lines 980-989. Task 4.1, lines 1166-1173. Task 5.1, lines 1264-1271.

**Source evidence:**

- `machines/nexus/default.nix:98-109` trusts Pylon because Pylon currently acts as an HTTP proxy.
- `modules/services/surmhosting/default.nix:363-380` enables `trustForwardHeader` and forwards `X-Forwarded-Host`.
- Traefik `v3.7.10`, `pkg/middlewares/forwardedheaders/forwarded_header.go`, `ServeHTTP` removes forwarded headers only for untrusted remote addresses.
- The same file's `rewrite` preserves a nonempty `X-Forwarded-Host`.
- Traefik `v3.7.10`, `pkg/middlewares/auth/forward.go`, `writeHeader` preserves those headers when `trustForwardHeader` is true.
- The plan's `/auth` matrix returns 200 for a configured public app. Task 1.6 selects that app through `X-Forwarded-Host`.

**Concrete failure sequence:**

1. A public request targets a restricted service through Pylon.
2. The request supplies `X-Forwarded-Host: music.apps.surma.technology`.
3. Pylon forwards packets without processing HTTP headers.
4. Pylon's masquerade changes the source to its trusted Tailscale address.
5. Nexus accepts the supplied forwarded host because that address appears in `trustedIPs`.
6. The router selects the restricted backend from the actual HTTP host.
7. Host-based forward-auth selects the public music policy from the supplied forwarded host.
8. Forward-auth returns 200, so Traefik permits the restricted request.

This sequence needs no compromised tailnet machine. It uses the public path that Section 3.3 explicitly protects.

The legacy `?app=` middleware prevents this specific substitution for compatibility services. It does not protect new-style services. Task 5.1 removes that protection from the migrated services.

**Required revision:** Remove HTTP-header trust from the public DNAT entrypoints. DNAT is not an HTTP proxy. Generate forward-auth metadata from the actual request, or otherwise guarantee its provenance before policy resolution.

Preserve temporary proxy trust only on an isolated migration path if that path still needs it.

**Acceptance check:** Through the real generated middleware, request a restricted service with a public app in `X-Forwarded-Host`. Repeat with a different allowlisted app. Both requests must enforce the actual target's policy. Cover both namespaces and the configuration after Task 5.1.

### 2. Critical — The publication and policy schema cannot represent the existing service topology

**Requirement:** Preserve existing services while adding per-service policy and secondary domains. Section 1.2 also excludes changes to `nixos-admin` behavior.

**Plan locations:** Section 4.9, lines 321-382. Task 2.1, lines 861-884. Task 3.2, lines 1002-1056. Task 3.4, line 1114. Task 5.1, lines 1264-1277.

**Source evidence:**

- `modules/services/surmhosting/default.nix:12-29,74-106` separates ports from a service-level allowlist.
- The same file, lines 154-179, applies one policy decision to every port of a service.
- The same file, lines 263-266 and 330-332, enables auth and constructs apps from nonempty legacy allowlists.
- `machines/nexus/service-brain-serve.nix:126-137` places private Brain and public Brain in one service.
- The same file, `brainServeStart` and `brainServePublicStart`, starts distinct servers on ports 8080 and 8081.
- `machines/pylon/service-brain-proxy.nix:3-8` restricts private Brain.
- `machines/pylon/service-public-brain-proxy.nix:3-7` leaves public Brain public.
- `machines/pylon/service-llm-proxy.nix:21-37` assigns three domains to three different ports.
- `machines/nexus/service-nexus-admin.nix:59-64,109-112` exposes the local admin server through an internal surmhosting route.
- `machines/nexus/service-rss.nix:3,11-12` exposes an internal FreshRSS route with `authType = "none"`.

**Concrete failure sequences:**

**Implicit publication:** Task 3.1 sets the global namespace. Section 4.9 then derives a public domain for every existing exposed port. No service-level public opt-in exists. A null `publicDomain` means “derive the default,” not “remain internal.”

The evaluated Nexus inventory includes these exposed services outside the explicit migration table:

- `admin`, `copyparty`, `firefly`, and `firefly-imp`.
- `lidarr`, `prowlarr`, `radarr`, and `sonarr`.
- `overview`, `rss`, `syncthing`, and `torrent`.

Leaving those files unchanged does not keep them internal. The default `authenticated` mode admits any valid GitHub session. This is a new access path, not preservation of current exposure. In particular, the plan publishes the admin route despite its stated non-goal.

**Brain policy collision:** Task 3.2 assigns `allowlist` to one Brain port and `public` to the other. The proposed `expose.access.mode` belongs to the service, not the port or logical app. One setting cannot express both rows. Selecting public opens private Brain. Selecting allowlist removes public access to public Brain.

**Alias collision:** Task 3.4 requests an alias on each matching LLM port. The proposed schema defines only service-level `expose.aliases`. Repeating all three aliases on all routers creates overlapping host rules for different backends. Defining aliases on port records instead fails the stated option schema.

**Auth removal:** Section 4.9 says the auth container wiring moves unchanged. Its existing `authEnabled` predicate depends only on `allowedGitHubUsers`. Retaining that predicate removes the auth container after Task 5.1 removes the last compatibility allowlist.

**Required revision:** Define the logical app separately from the container where their boundaries differ. Give public publication an explicit opt-in or explicit disabling value. Define aliases at the same routing scope as public domains.

Compute auth enablement from the new policy model. Do not infer it solely from legacy allowlists. Preserve the admin UI when its intended topology contains no legacy allowlist.

The HedgeDoc split legitimately repeats one domain across two ports of the same app. The uniqueness assertion must reject cross-app conflicts without rejecting that split.

**Acceptance check:** Snapshot the generated routers and policy topology for the entire Nexus inventory. Verify private Brain, public Brain, all three LLM ports, and internal-only services. Repeat without any `allowedGitHubUsers` definition.

### 3. High — The staged deployment breaks existing routes before cutover and cannot support the stated rollback

**Requirement:** Preserve services, domains, internal callers, and rollback paths. Section 5 promises no public change during the Nexus deployment.

**Plan locations:** Section 5, lines 429-433. Task 2.2, lines 905-919. Task 3.3, lines 1069-1101. Task 3.5, lines 1127-1138. Section 8, lines 1315-1329.

**Source evidence:**

- `machines/pylon/service-hedgedoc-proxy.nix:4-7` forwards to an internal Nexus hostname on port 80 and rewrites the host.
- The same pattern exists in Pylon's Gitea, Dump, Brain, public Brain, Scout Static, and Jazzy proxy files.
- `machines/pylon/service-music-proxy.nix:9-12` also targets an internal Nexus HTTP hostname without a new port.
- `modules/services/surmhosting/default.nix:159-179` builds those backend URLs and internal routers.
- `apps/surm-auth/main.go:51-59` fixes the callback to `base_url + "/callback"`.
- `apps/surm-auth/handlers/callback.go:36-49,64-80` expects the old state and app configuration on Pylon.
- `modules/programs/gitea-cli/default.nix:27-30,50-56` configures an internal HTTP URL outside `machines/nexus/`.
- `assets/skills/hedgedoc/SKILL.md:34` uses the old internal HTTP base URL.
- `assets/skills/music/SKILL.md:25-28,37,74,178,191` uses the old internal service URLs.
- `assets/skills/nexus-admin/SKILL.md:12,64-67,95` uses port 80 throughout its operational examples.

**Concrete failure sequence:**

1. Task 3.5 deploys Nexus with internal routers only on port 8081.
2. Pylon remains on its existing generation.
3. A legacy public request reaches Pylon successfully.
4. Pylon sends HTTP to the internal Nexus hostname on port 80.
5. That internal router no longer exists on port 80.
6. The request fails rather than reaching its existing backend.

A global HTTP redirect would not restore this flow. Pylon's rewritten internal hostname would redirect toward an internal HTTPS name that the target design does not serve.

Redeploying the previous Pylon generation recreates this same broken flow while Nexus remains on the new generation. Therefore, the proposed one-host rollback cannot restore legacy services.

**The pre-cutover checks target the wrong server:** Task 0.1 points the apps wildcard at Pylon. Task 3.5 uses normal DNS rather than `--resolve` or an equivalent override. A tailnet client still reaches Pylon. Pylon has neither the new routes nor Nexus's new wildcard certificate.

Even an override for `auth.apps.surma.technology` alone cannot prove the complete OAuth flow. The provider still sends the callback to `auth.surma.technology`, which reaches Pylon's v1 service before cutover. That service does not create the planned `_surm_auth2` session.

**The internal migration inventory is incomplete:** Updating only the listed Nexus files leaves the Gitea CLI and Scout skills on port 80. A verbal note about the admin URL does not update the installed consumers. This does not require changes to shell aliases or SSH forwarding.

**Required revision:** Specify an intermediate configuration that supports both sides of each deployment boundary. Alternatively, state an approved maintenance window and a coordinated rollback of both hosts. Do not claim continuity without such a configuration.

Test Nexus directly before cutover. For browser OAuth, route both the login host and the fixed callback host to the intended auth instance. Preserve or explicitly update all internal HTTP consumers.

Task 2.2 also needs a precise compatibility contract. Parsing legacy YAML keys does not preserve v1 behavior after replacing the package and cookie format. Existing YAML lacks the required v2 policy path, domains, and mode.

**Acceptance check:** Exercise old Pylon with new Nexus before deployment. Exercise the reverse rollback state separately. Verify old public domains, internal API callers, and the callback round trip in each supported state.

### 4. High — The Nexus bootstrap does not connect the pinned options, credentials, and writable state

**Requirement:** Nexus must terminate HTTPS. The admin UI and runtime grants must work on the first deployment. Repository instructions require executable verification rather than an assumed successful start.

**Plan locations:** Sections 4.3 and 4.9-4.10. Task 0.2, lines 452-459. Tasks 1.3 and 1.9. Task 2.1, line 876. Task 2.2, lines 908-915. Task 3.1, lines 948-976. Task 3.4, lines 1105-1116.

**Source evidence:**

- **nixpkgs/**`nixos/modules/services/web-servers/traefik.nix:110-119` defines `services.traefik.environmentFiles`.
- The same file, line 132, maps it to `systemd.services.traefik.serviceConfig.EnvironmentFile`.
- `systemd.services.traefik.environmentFiles` is not an option. An in-memory evaluation of the exact assignment produced that error.
- `modules/services/surm-auth/default.nix:134-139` uses `DynamicUser = true` and `ProtectSystem = "strict"`.
- That unit declares neither `StateDirectory`, writable paths, nor credential loading.
- `modules/services/surmhosting/default.nix:300-325` mounts the host secret directory and directs Go to ordinary files inside it.
- `apps/surm-auth/config/config.go:58-79` reads those files as the service user.
- `modules/secrets/default.nix:58-68,88-95` creates target files as root and starts its own independent oneshot unit.
- `machines/pylon/service-surm-auth.nix:11-25` currently uses readable files and a traversable directory. Task 3.1 changes those modes to root-only values.
- Lego `v5.3.1`, `providers/dns/cloudflare/cloudflare.go`, `NewDNSProvider` requires zone lookup permission with DNS edit permission.
- Lego `v5.3.1`, `providers/dns/cloudflare/wrapper.go`, `ZoneIDByName` invokes `clientRead.ZonesByName` before it can create records.

**Concrete failure sequences:**

**Evaluation:** Task 2.1 adds the invalid systemd option. Evaluation fails when Nix forces the Traefik unit. Reading only `services.traefik.enable` does not force that failure. This review reproduced both outcomes.

**Auth startup:** Task 3.1 creates `/var/lib/surm-auth` as root, mode 0700. It creates the three credential files as root, mode 0600. The dynamic service user cannot traverse the mounted secret directory or read those files. `LoadSecrets` fails, and the service restarts without opening its HTTP listener.

Making the bind mount writable does not solve the policy problem. `ProtectSystem = "strict"` still makes the service filesystem read-only outside explicit exceptions. The dynamic user also lacks ownership of the planned state directory.

**DNS bootstrap:** After correcting the option, the documented token has only `Zone:DNS:Edit`. Lego attempts a zone lookup. That lookup requires `Zone:Zone:Read`, so the documented token cannot complete certificate issuance.

**LLM credential migration:** Task 3.4 copies Pylon's secret declarations unchanged. Nexus already declares `llm-proxy-secret.target` as `/var/lib/key-poller/receiver-secret`. The copied declaration uses `/var/lib/llm-proxy-credentials/receiver-secret`. Nix reports conflicting definitions. This review reproduced that exact conflict.

The other copied targets have a separate interaction. Nexus already defines commands for `llm-proxy-client-key` and `openrouter-api-key` in `machines/nexus/service-scout.nix:81-85,171-175`. The secrets module gives `command` precedence over `target`. Adding targets alone creates or touches the destination files but sends the decrypted content to the existing Scout commands instead.

A one-time copy of credentials conceals that problem until a fresh host or a later secret change. It does not preserve the declaration's meaning.

**Required revision:** Specify one complete bootstrap contract:

- Use `services.traefik.environmentFiles` or the correct `serviceConfig.EnvironmentFile` field.
- Give the Cloudflare token both required permissions within the existing zone scope.
- Preserve Traefik's ownership of its ACME state directory.
- Order credential generation before the services and containers that consume it.
- Separate immutable credentials from mutable policy state.
- Use credential loading or explicit readable ownership for auth secrets.
- Give the auth service a persistent, owned, writable state directory compatible with its sandbox.
- Supply concrete defaults for `policy.file` and `policy.auditFile`.
- Preserve both the key poller and LLM receiver credential paths without conflicting declarations.
- Extend the existing secret commands when multiple consumers need the same decrypted value.

Task 3.1 does not set `auth.policyFile` or `auth.auditFile`, although both proposed defaults are null. Task 1.3 requires `policy.file`. The plan must resolve that mismatch explicitly.

The Task 2.2 host-level check also addresses the wrong module scope. Nexus imports `surm-auth` inside its container, not into host `services`. The correct eventual check is under `config.containers.surm-auth.config.services.surm-auth`.

**Acceptance check:** Use an isolated first-boot test with empty state and the real unit definitions. Verify credential reads, policy mutation, restart persistence, and access to every LLM consumer. Run the packaged binary with valid test configuration, not only `/dev/null`.

### 5. High — The forwarding rules omit UDP and do not provide a return path for public Minecraft traffic

**Requirement:** Forward TCP and UDP on ports 80 and 443. Preserve Minecraft and Gitea SSH. Section 1.2 names those preserved services explicitly.

**Plan locations:** Section 3.2, lines 93-99. Task 4.1, lines 1152-1179. Section 7, lines 1292-1313. Task 5.2, lines 1283-1288.

**Source evidence:**

- Task 4.1 lists four rules, all with `proto = "tcp"`.
- Its custom masquerade matches only `ip daddr ${nexusTsV4}`.
- `machines/pylon/service-minecraft-proxy.nix:4-7,21-22` sends Minecraft to Citadel at `100.70.63.93`.
- `machines/citadel/service-minecraft.nix:27,103-109` exposes that TCP service through a container forward.
- **nixpkgs/**`nixos/modules/services/networking/nat-nftables.nix:18,97-105` restricts generic SNAT by egress or ingress conditions.
- External traffic enters through `enp1s0`. The generated loopback SNAT explicitly requires `iifname != "enp1s0"`.
- The same file, lines 79-86, constructs a protocol-specific map. A surrounding `{ tcp, udp }` condition does not add missing UDP entries.

**Concrete failure sequences:**

**UDP:** A datagram reaches Pylon on UDP port 443 or 80. It has no matching DNAT map entry. It cannot reach Nexus through the promised edge path.

**Minecraft:** A public TCP connection reaches Pylon port 25565. DNAT changes its destination to Citadel, but none of the proposed SNAT rules matches this flow. Citadel receives the original public source. Its return route does not return through the same Pylon NAT connection. The connection fails. Strict reverse-path checks can reject it even earlier.

Nexus-bound web and SSH traffic matches the custom rule. Minecraft does not. The working hairpin case does not prove the external case because the generated loopback SNAT treats them differently.

**Required revision:** Include the required UDP forwards. Cover Citadel as well as Nexus in the source NAT rules. Prefer explicit forwarded destinations and ports rather than all traffic to one host.

The requirement asks for UDP forwarding. It does not independently require HTTP/3. If the intended UDP service is HTTP/3, also configure Nexus's listener and UDP firewall rule. Plain `address = ":443"` defaults to TCP in Traefik.

**Acceptance check:** Test external and hairpin TCP separately for both destinations. Test UDP packet arrival on Nexus. Add Minecraft to the cutover matrix, which currently checks only Gitea SSH.

The pinned NAT module does support the proposed option names and IPv4 forwarding. `loopbackIPs` also creates an output-chain rule for Pylon-originated requests. No replacement of that mechanism is necessary.

## Non-blocking implementation notes and bounded uncertainties

These notes do not add ranked release findings. They identify implementation details and acceptance cases that the revised plan should resolve. They do not claim failures in nonexistent v2 code.

### Go model, policy store, and tests

The existing dependencies can support the proposed implementation. Stable provider IDs already arrive from GitHub in `apps/surm-auth/auth/github.go:62-80`. Adding the provider name does not require a new OAuth library.

The concrete task sketches are not a directly compilable patch:

- Task 1.3 omits the loaded `Session.CookieSecret` field that `main.go:63,72-73` currently consumes.
- Task 1.5 adds `ResolveUsername` to the concrete provider, but not the interface in `auth/provider.go:5-13`.
- Task 1.9 resolves seed users before its stated “build providers” step.
- Tasks 1.3 through 1.9 change coupled APIs. Their intermediate “all tests pass” claims need compatibility shims or a revised task order.

The store tests should distinguish these states explicitly:

- First startup without a policy file.
- Corruption after a successful in-process load.
- Cold startup with corruption and no in-memory good copy.
- Failed disk commit with the previous in-memory policy still active.
- Removal of the last seed grant followed by restart.
- Two concurrent changes to the last-admin set.

Section 4.3 and Task 1.1 require unknown JSON fields to survive writes. Plain structs in the sketch do not provide that behavior automatically. Use explicit raw-field preservation if the requirement remains. Do not infer a need for a broader storage abstraction.

Task 1.1's “skip when app already has grants” differs from Task 1.9's “skip when the grant exists.” Neither wording clearly distinguishes an intentionally empty grant set from an unimported app. Define a one-time import marker or an equally explicit rule before implementing restart behavior.

Bootstrap roles also need a clear ownership rule. Section 4.7 reasserts configured administrators on every startup. Section 4.2 assigns runtime roles to the UI. An administrator listed in Nix therefore needs either a non-removable label or an explicit exception to UI ownership.

The sample configuration uses app key `hedgedoc`, but Nexus uses service key `hedgedoc2`. Tasks 3.5 and 5.1 expect a `hedgedoc` grant. Specify the stable policy key rather than deriving it inconsistently from a display name, hostname, or container name.

No tests currently exist under `apps/surm-auth/`. The proposed tests are new work, not an existing passing safety net.

### OAuth, sessions, and the admin UI

The JWT claim design fits `github.com/golang-jwt/jwt/v5` and avoids username-based identity. Keep policy grants and roles outside the JWT. That permits live revocation without reissuing every session.

The current validator accepts the HMAC family, not exclusively HS256 (`auth/session.go:80-85`). The revised tests should state the desired algorithm and mandatory identity claims precisely. This observation does not establish token forgery without a signing key.

Task 1.7 adds a nonce to signed state. It does not specify a browser-bound value, expiry, or one-time consumption. Existing `auth/state.go:18-83` verifies only the signature. Clarify those semantics and test callbacks without an initiating browser transaction. This review did not attempt an OAuth exploit against a live service.

The admin POST token design can use standard HMAC functions. Test an expired token, the wrong subject, and each mutating endpoint. `GET /logout` remains an explicitly allowed state change, so “every mutation requires POST” needs a logout exception or a changed endpoint contract.

The callback tests should include anonymous navigation directly to `/admin`. The auth host is not necessarily an app entry. Existing `handlers/callback.go:64-70` rejects unknown apps. The revised handler needs an explicit successful auth-host login path rather than blindly preserving that check.

Task 1.5's API URL overrides cover user requests, not necessarily the token exchange endpoint. `auth/github.go:25,45` uses `oauth2.Config.Endpoint` for the exchange. Configure that endpoint in same-package tests, or inject an appropriate test provider. Do not let the claimed offline tests contact GitHub.

The package already copies the entire templates directory (`packages/surm-auth/default.nix:20-23`). It does not need a new list of template filenames. Its wrapper already sets `SURM_AUTH_TEMPLATES` at lines 28-30.

Current handlers parse templates when they construct the handler, not per request (`handlers/login.go:14-24`, `handlers/callback.go:15-25`). Task 1.8's claimed existing pattern is inaccurate. Reuse the constructor-time approach unless the implementation needs a different behavior.

Handler tests run from their package directory. Their template fixtures must not depend on `./templates` pointing at the application root. A `/dev/null` configuration failure also does not prove that packaged templates render.

The plan's standard library additions alone do not require a new `vendorHash`. Change the hash only if the dependency closure actually changes.

### TLS, internal routes, and domain boundaries

`certificatesResolvers.cloudflare.acme.dnsChallenge.provider` and `entryPoints.websecure.http.tls.certResolver` match Traefik's configuration structure. DNS-01 can issue certificates before public routing changes.

There is no automatic redirect merely because both `web` and `websecure` appear on a router. The revised generated configuration must explicitly implement the promised redirect. Traefik's `pkg/provider/traefik/internal.go`, `redirection`, requires `http.redirections.entryPoint` configuration. The current surmhosting module does not configure it.

The specified source ranges include container IPv4 addresses because `10.201.0.0/16` lies inside `10.0.0.0/8`. Thus, the explicit source rule can admit those callers without a functioning veth wildcard.

Do not rely on `trustedInterfaces = [ "ve-+" ]` as an independent nftables guarantee. `machines/nexus/service-postgresql.nix:117-124` already documents that mismatch. The pinned firewall module emits those names literally in an `iifname` set.

Testing a Tailscale-only address from the public internet does not test hostile host selection at the public edge. The revised test must address Pylon's public IP with an internal HTTP host. Finding 1 requires a separate forwarded-host test.

The listed cookies cover both legacy and apps subdomains. They cannot cover a secondary domain outside `surma.technology`. If the confirmed requirement includes such a domain, the parent agent must request a separate session design decision.

The Cloudflare token scope also covers only that zone. Certificate support for other zones does not follow from a generic `aliases` list.

### Explicitly deferred ideas

The plan explicitly defers these items. This review does not treat them as release requirements:

- A second OAuth provider.
- Service tokens for trusted internal callers.
- Client-IP fidelity through PROXY protocol.
- IPv6 for the new apps namespace.
- Changes to music access policy.
- New primary base URLs for HedgeDoc and Gitea.

Preservation of existing domains is different from adding IPv6. Pylon already has a public IPv6 address (`machines/pylon/default.nix:56-66`). I did not inspect live AAAA records. Existing AAAA records need an inventory before an IPv4-only cutover can claim full legacy-domain preservation.

## Read-only verification record

All commands below ran from the repository directory unless their path is absolute. No command deployed a configuration. The in-memory module overlays did not edit Nix files.

### Repository and input identity

```bash
git status --short --branch
git rev-parse HEAD
sha256sum auth-rework.md
nix eval --offline --no-write-lock-file --impure --raw \
  --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath'
```

Results before the report:

```text
## scout/dynamic-service-access...origin/main [behind 3]
?? auth-rework.md
9345a14cf8f4cc8bd360bf475e7f558134b20c9f
e3d3056ded5c827834700d71d6153073807527583643ce4639c2ef249dbaf8a3  auth-rework.md
/nix/store/6bf80a7m11xpxdh0qi5k83721lqxk11s-source
```

An initial attempt to evaluate `.#inputs.nixpkgs.outPath` failed because the flake does not export that output. The `builtins.getFlake` command above resolved the input successfully.

### Package versions

```bash
nix eval --offline --no-write-lock-file --impure --json --expr '
let f = builtins.getFlake (toString ./.);
    p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
in {
  traefikVersion = p.traefik.version;
  traefikSource = toString p.traefik.src;
  goVersion = p.go.version;
}'
```

Result:

```json
{"goVersion":"1.26.6","traefikSource":"/nix/store/2vmm123cgnmq3198jp2qkh1kkwhx6y90-source","traefikVersion":"3.7.10"}
```

That Traefik source path was not present locally. I read the versioned upstream source instead. I did not realize the derivation.

### Options and existing topology

```bash
nix eval --offline --no-write-lock-file --impure --json --expr '
let f = builtins.getFlake (toString ./.);
    p = f.nixosConfigurations.pylon;
    n = f.nixosConfigurations.nexus;
in {
  systemdEnvironmentFilesOption = builtins.hasAttr "environmentFiles"
    (p.options.systemd.services.type.getSubOptions []);
  traefikEnvironmentFilesOption = builtins.hasAttr "environmentFiles"
    p.options.services.traefik;
  filterForward = p.config.networking.firewall.filterForward;
  nftables = p.config.networking.nftables.enable;
  natExternal = p.config.networking.nat.externalInterface;
  nexusServices = builtins.mapAttrs (_: s: {
    expose = s.expose.enable;
    ports = s.expose.ports;
  }) n.config.services.surmhosting.services;
}'
```

Results:

- The systemd-level `environmentFiles` option is absent.
- The Traefik-level `environmentFiles` option exists.
- `filterForward = false`, `nftables = true`, and `natExternal = "enp1s0"`.
- The full inventory contains the internal services listed in finding 2.
- Brain has two exposed ports in one service.

An initial expression omitted `[]` from `getSubOptions` and failed with “expected a set but found a function.” The corrected command above succeeded.

A separate evaluated selection returned these facts:

- Nexus has no host-level `options.services.surm-auth`.
- Pylon's HedgeDoc backend is `http://hedgedoc2.nexus.hosts.100.83.198.90.nip.io:80`.
- The existing auth unit uses `DynamicUser` and `ProtectSystem = "strict"`.
- Nexus's receiver secret target is `/var/lib/key-poller/receiver-secret`.

### Invalid option reproduction

```bash
nix eval --offline --no-write-lock-file --impure --json --expr '
let f = builtins.getFlake (toString ./.);
    p = f.nixosConfigurations.nexus.extendModules {
      modules = [{
        systemd.services.traefik.environmentFiles = [
          "/var/lib/traefik/cloudflare.env"
        ];
      }];
    };
in p.config.systemd.services.traefik.serviceConfig'
```

Result: exit status 1.

```text
error: The option `systemd.services.traefik.environmentFiles' does not exist.
```

Evaluating only `p.config.services.traefik.enable` with the same overlay returned `true`. It did not force the invalid unit. A successful leaf evaluation is not a whole-system gate.

### Conflicting LLM secret reproduction

```bash
nix eval --offline --no-write-lock-file --impure --json --expr '
let f = builtins.getFlake (toString ./.);
    p = f.nixosConfigurations.nexus.extendModules {
      modules = [{
        secrets.items.llm-proxy-secret.target =
          "/var/lib/llm-proxy-credentials/receiver-secret";
        secrets.items.llm-proxy-secret.mode = "0644";
      }];
    };
in p.config.secrets.items.llm-proxy-secret.target'
```

Result: exit status 1.

```text
error: The option `secrets.items.llm-proxy-secret.target' has conflicting definition values:
- "/var/lib/llm-proxy-credentials/receiver-secret"
- "/var/lib/key-poller/receiver-secret"
```

### Generated NAT check

```bash
nix eval --offline --no-write-lock-file --impure --json --expr '
let f = builtins.getFlake (toString ./.);
    p = f.nixosConfigurations.pylon.extendModules {
      modules = [{ networking.nat.forwardPorts = [
        { sourcePort = 80; destination = "100.83.198.90:80";
          proto = "tcp"; loopbackIPs = [ "192.0.2.1" ]; }
        { sourcePort = 443; destination = "100.83.198.90:443";
          proto = "tcp"; loopbackIPs = [ "192.0.2.1" ]; }
        { sourcePort = 2222; destination = "100.83.198.90:2222";
          proto = "tcp"; loopbackIPs = [ "192.0.2.1" ]; }
        { sourcePort = 25565; destination = "100.70.63.93:25565";
          proto = "tcp"; loopbackIPs = [ "192.0.2.1" ]; }
      ]; }];
    };
in {
  nat = p.config.networking.nftables.tables.nixos-nat.content;
  forwarding = p.config.boot.kernel.sysctl."net.ipv4.conf.all.forwarding";
}'
```

Result: the evaluation succeeded. `forwarding` is true. The generated maps contain four TCP entries and no UDP entries. The rules contain both prerouting and output hairpin DNAT. Generic masquerade uses `oifname "enp1s0"`. Loopback masquerade requires `iifname != "enp1s0"`.

`192.0.2.1` is a documentation address used only for this evaluation. It is not Pylon's asserted public address. The overlay retained the baseline internal NAT ranges. Removing surmhosting does not repair the identified Citadel return-path omission.

### Targeted source searches

```bash
rg --files -g 'AGENTS.md' -g 'INTENT.md' -g '*test*' \
  modules/services/surmhosting modules/services/surm-auth \
  apps/surm-auth packages/surm-auth
rg -n 'expose|rule|host|url|allowedGitHubUsers' \
  machines/pylon/service-*-proxy.nix
rg -n 'nexus\.hosts\.|hedgedoc2\.nexus|10\.201\.' \
  assets/skills modules machines/scout profiles \
  --glob '*.md' --glob '*.nix' --glob '*.nu'
rg -n 'forwardedAgentMatch|IdentityAgent|ForwardAgent' \
  profiles/home-manager/base.nix
```

The first search returned no local tests or additional instruction files in the reviewed auth directories. The other searches established the proxy inventory, omitted HTTP consumers, and preserved SSH configuration.

I used the read tool for the complete Go application, both templates, `go.mod`, `go.sum`, and the package definition. I also read the relevant Nix modules and machine service files. I read the full NAT and Traefik NixOS modules from the resolved input.

### External dependency reads

`command -v web-search` returned `/etc/profiles/per-user/containeruser/bin/web-search`.

The successful source reads used these exact commands:

```bash
web-search fetch https://go-acme.github.io/lego/dns/cloudflare/
web-search fetch --mode static https://raw.githubusercontent.com/traefik/traefik/v3.7.10/pkg/middlewares/forwardedheaders/forwarded_header.go
web-search fetch https://raw.githubusercontent.com/traefik/traefik/v3.7.10/pkg/middlewares/auth/forward.go
web-search fetch --mode static https://raw.githubusercontent.com/traefik/traefik/v3.7.10/go.mod
web-search fetch --mode static https://raw.githubusercontent.com/traefik/traefik/v3.7.10/pkg/provider/traefik/internal.go
web-search fetch --mode static https://raw.githubusercontent.com/traefik/traefik/v3.7.10/pkg/config/static/entrypoints.go
web-search fetch --mode static https://raw.githubusercontent.com/go-acme/lego/v5.3.1/providers/dns/cloudflare/cloudflare.go
web-search fetch --mode static https://raw.githubusercontent.com/go-acme/lego/v5.3.1/providers/dns/cloudflare/wrapper.go
web-search fetch https://raw.githubusercontent.com/golang-jwt/jwt/v5.2.0/parser.go
web-search fetch https://raw.githubusercontent.com/golang/oauth2/v0.15.0/oauth2.go
```

Traefik's manifest pins Lego v5.3.1. The versioned Lego source confirms the Cloudflare permission requirement. The versioned Traefik source confirms forwarded-header preservation, explicit redirects, and TCP defaults.

An initial forwarded-header URL used `pkg/server/middleware/forwardedheaders/forwarded_header.go`. It returned 404. The successful URL above uses `pkg/middlewares/forwardedheaders/forwarded_header.go`.

### Checks not executed

I did not run Go tests, package builds, flake checks, or VM tests. The Go executable is absent from PATH. This review's scope forbids tool installation and implementation writes.

I did not execute the plan's commands that merge stderr and stdout. Tasks 2.3 and 3.5 conflict with `assets/AGENTS.md:25-30`. Their replacement checks should preserve stderr separately and must not filter away failures.

I did not verify live DNS records, provider credentials, container permissions, certificates, or packet paths. No runtime success follows from these source and evaluation checks.

## Assumptions, remaining gaps, and next decision

**Assumptions:** The existing LAN and tailnet remain trusted, as the plan states. The single-host deployment remains acceptable. No additional provider or client-IP requirement applies.

**Remaining input:** Confirm whether secondary domains include registrable domains outside `surma.technology`. Confirm whether any currently internal service should become public. The plan must not choose that publication policy implicitly.

**Remaining verification:** After revision, evaluate both complete machine configurations. Build the package and test the real container unit. Prove the migration's intermediate states and rollback before production changes.

**Changed file:** Only `auth-rework-review.md`.

**Next action:** Revise the plan to resolve findings 1-5. Do not deploy this plan as written.
