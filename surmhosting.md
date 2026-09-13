# Surmhosting Standalone Flake Implementation Plan

**Status:** This document is a proposal. It does not authorize implementation, repository creation, removal, publication, or deployment.

**Goal:** Make Surmhosting reusable while preserving the current Nexus and Citadel behavior.

**Architecture:** Stage 1 organizes Surmhosting inside nixenv. Stage 2 copies that tree into a new standalone repository and flake.

**Reviewed baseline:** `17c48975634079e9bc43b8274eaacbdf5686cd22` on 2026-09-12.

## 1. Approval boundaries

This plan separates the work into two stages.

Stage 1 changes only the nixenv repository. Nixenv remains the source owner throughout this stage.

Stage 2 creates a new repository with fresh history. It then changes nixenv to consume that repository.

Each stage needs separate approval. Stage 1 approval does not authorize Stage 2.

Neither stage authorizes a NixOS deployment. Any Nexus or Citadel deployment needs separate approval.

Stage 2 also needs separate approval before these actions:

- Creating a repository or remote
- Writing outside the current working directory
- Removing the local implementation from nixenv
- Pushing a new repository

Publication review and deployment rollback remain outside this plan.

## 2. Confirmed decisions

The following decisions replace earlier alternatives in this document.

1. Stage 1 starts with a mechanical relocation commit.
2. The relocation commit must not change effective host behavior.
3. Later ownership changes use separate commits and focused checks.
4. Surmhosting manages public firewall ports 80 and 443 only.
5. Nexus keeps its existing port 8081 rule in `machines/nexus/default.nix`.
6. Users own service-to-service firewall access.
7. Supplied NixOS container settings own explicit network addresses.
8. Surmhosting supplies generated container addresses through `lib.mkDefault`.
9. Traefik reads each final evaluated container address.
10. The auth container keeps explicit auth network options.
11. Stage 1 includes no extraction-isolation test or coupling token search.
12. Stage 2 exposes any remaining repository dependency through normal standalone evaluation.
13. The user owns and prepares the auth state host path.
14. Surmhosting mounts the auth state path but never creates or modifies it.
15. Stage 2 starts a new repository without imported Git history.
16. Nixenv removes all Surmhosting package and component check outputs during Stage 2.
17. The standalone flake exports x86 Linux and ARM Linux packages.
18. CI builds and tests x86 Linux. ARM Linux receives evaluation-only coverage.
19. The repository will probably start as a private Gitea repository.
20. The user handles publication review.
21. Deployment rollback is outside this plan.
22. Runtime state and credential paths must stay outside the Nix store.
23. Traefik removes CIDR suffixes from final container addresses used in URLs.
24. The internal auth module exposes local OAuth endpoint seams for offline tests.

## 3. Product scope

Surmhosting remains an opinionated NixOS hosting module.

Surmhosting accepts an existing NixOS container configuration. It applies defaults and adds the container to its service inventory.

Surmhosting also accepts an existing host backend. This compatibility path supports local and remote services.

Surmhosting enables and configures Traefik. Consumers do not need a separate Traefik module for generated routes.

Surmhosting opens the public firewall ports required by its public entrypoints.

Surmhosting bundles the `surm-auth` source, package, NixOS module, and tests.

The auth runtime remains controlled by `services.surmhosting.auth.enable`. Citadel can continue to disable it.

Surmhosting preserves its current optional Podman integration. That integration lets Traefik discover externally declared OCI workloads.

OCI workloads remain ordinary `virtualisation.oci-containers` declarations. Their declarations own images, ports, volumes, and Traefik labels.

Dockerfiles, Compose files, and a unified OCI service schema remain follow-up work.

## 4. Explicit non-goals

Stage 1 does not redesign the routing model.

Stage 1 does not rename the `services.surmhosting` option namespace.

Stage 1 does not remove legacy `expose.port`, `expose.ports`, or `allowedGitHubUsers` compatibility.

Stage 1 does not change current app keys, domains, routes, access modes, or middleware behavior.

Stage 1 does not replace NixOS containers with OCI containers.

Stage 1 does not make Surmhosting a secret manager.

Stage 1 does not manage workload-specific bind mounts.

Stage 1 does not manage service-to-service firewall rules.

Stage 1 does not prove that the component works outside nixenv.

Stage 1 does not move production credentials or state.

Stage 1 does not clean inactive Pylon rollback files.

Stage 1 does not repair the unrelated `testcontainer` configuration.

Stage 1 does not repair unrelated root flake failures.

Stage 2 does not import historical commits into the new repository.

Stage 2 does not preserve Surmhosting package or check aliases in nixenv.

Stage 2 does not deploy the external module to any host.

## 5. Current repository inventory

The current implementation spans these paths:

- `modules/services/surmhosting/default.nix`
- `modules/services/surmhosting/tests.nix`
- `modules/services/surm-auth/default.nix`
- `apps/surm-auth/**`
- `packages/surm-auth/default.nix`
- `packages/surm-auth/e2e-check.nix`
- `pkgs/surm-auth/default.nix`
- `modules/core/checks.nix`
- `packages/update-all/update-all.nu`

Nexus declares 25 Surmhosting services. Citadel declares three Surmhosting services.

Nexus also runs these OCI workloads:

- `machines/nexus/service-jellyfin.nix`
- `machines/nexus/service-jaeger.nix`

Both OCI workloads publish Traefik labels outside the Surmhosting service inventory.

Pylon contains inactive Surmhosting files. Its current configuration does not import them.

## 6. Ownership boundary

### 6.1 Surmhosting-owned behavior

Surmhosting owns these behaviors:

- Enable and configure Traefik
- Generate Traefik entrypoints, routers, services, middleware, and certificate resolvers
- Create NixOS containers from supplied container configurations
- Supply default container names and addresses
- Configure default NAT for its generated private networks
- Open public firewall ports 80 and 443
- Enable Podman discovery when `docker.enable` is true
- Build and run the bundled auth container when auth is enabled
- Convert declared apps into auth policy configuration
- Mount declared credential files into the auth container
- Mount the declared state directory into the auth container

### 6.2 Consumer-owned behavior

The consumer owns these behaviors:

- Define each workload through the supplied NixOS container configuration
- Override Surmhosting defaults through the NixOS module system
- Define workload users, packages, services, devices, and bind mounts
- Declare OCI workloads and their Traefik labels
- Create and protect all credential files
- Choose the secret manager and its unit names
- Create and protect the auth state host directory
- Configure service-to-service firewall access
- Configure any access to the internal port
- Supply public domains and the external network interface
- Override native NixOS NAT settings for custom container networks
- Control production state, deployment, and rollback

### 6.3 Firewall boundary

Surmhosting opens port 80 when its public HTTP entrypoint exists.

Surmhosting opens port 443 when TLS is enabled.

Surmhosting never adds `internalPort` to a firewall rule.

Surmhosting never adds trusted interfaces or trusted source ranges.

Nexus keeps this host-owned rule:

```nix
networking.firewall.extraInputRules = ''
  ip saddr { 10.0.0.0/8, 100.64.0.0/10 } tcp dport 8081 accept comment "surmhosting internal HTTP"
'';
```

The current ineffective `ve-+` trusted-interface value leaves Surmhosting during the firewall ownership commit.

### 6.4 Auth state and credential boundary

The consumer supplies every host credential path.

The consumer also supplies `services.surmhosting.auth.stateHostPath` when auth is enabled.

Every runtime path must be a quoted absolute path outside the Nix store.

Surmhosting mounts these paths at fixed container locations.

Surmhosting does not create, decrypt, chmod, chown, or inspect the host paths.

Nexus creates its state and credential directories in `machines/nexus/service-surm-auth.nix`.

## 7. Compatibility contract

Stage 1 keeps these public option paths:

```nix
services.surmhosting.enable
services.surmhosting.externalInterface
services.surmhosting.containeruser
services.surmhosting.containerLimits
services.surmhosting.tls
services.surmhosting.appsNamespace
services.surmhosting.internalPort
services.surmhosting.dashboard.enable
services.surmhosting.docker.enable
services.surmhosting.hostname
services.surmhosting.services
services.surmhosting.auth
```

The service submodule keeps these backend fields:

```nix
host
container
containerName
containerService
expose
```

The `container` value remains a pass-through NixOS container configuration.

The default container name remains `lc-<first-ten-service-characters>`.

The default service addresses remain `10.201.<lexical-index>.1` and `10.201.<lexical-index>.2`.

The default auth addresses remain `10.202.0.1` and `10.202.0.2`.

Surmhosting sets generated container values with `lib.mkDefault`.

An explicit value in the supplied container configuration wins through normal NixOS option priority.

Traefik reads `config.containers.<name>.localAddress` after all module definitions merge.

For URL construction, Traefik removes an optional CIDR suffix from that final address.

An exposed container must have a non-null IPv4 local address.

The container keeps its complete configured value, including any CIDR suffix.

Current Nexus and Citadel declarations must not need route rewrites.

Current container names, routes, service addresses, and middleware names must remain stable unless the consumer already overrides them.

The mechanical relocation commit permits no semantic configuration change.

Store paths can change when source paths move. Such changes require `nix-diff` inspection and an explicit explanation.

## 8. New Stage 1 options

Stage 1 adds only options needed for ownership transfer.

### 8.1 Auth unit dependencies

Add this option:

```nix
services.surmhosting.auth.unitDependencies = {
  wants = [ ];
  requires = [ ];
  after = [ ];
};
```

The module applies these values to `container@surm-auth.service`.

The defaults name no secret-manager unit.

Nexus sets `requires` and `after` to `[ "secrets.service" ]`.

### 8.2 Traefik unit dependencies

Add this option:

```nix
services.surmhosting.tls.unitDependencies = {
  wants = [ ];
  requires = [ ];
  after = [ ];
};
```

The module applies these values to `traefik.service`.

The defaults name no secret-manager unit.

### 8.3 Auth state path

Add this option:

```nix
services.surmhosting.auth.stateHostPath = null;
```

Use `types.nullOr types.externalPath`.

This type accepts quoted absolute runtime paths outside the Nix store.

It rejects path literals and store-backed strings.

When auth is enabled, an assertion requires a non-null value.

The module mounts the path at `/var/lib/private` inside the auth container.

The module creates no temporary-files rule for this path.

### 8.4 Auth credential paths

Keep the three existing credential path names.

Change their types to `types.nullOr types.externalPath` in the public module.

Use `types.externalPath` for the corresponding required options in the internal auth module.

This change intentionally rejects store-backed credentials. Current Nexus string values remain valid.

Use each configured path as the source for its matching read-only auth mount.

The fixed container paths remain:

- `/var/lib/secrets/github-client-id`
- `/var/lib/secrets/github-client-secret`
- `/var/lib/secrets/cookie-secret`

The module creates no credential host directory.

Focused tests must accept quoted `/var/lib/...` paths and reject Nix store paths.

### 8.5 Auth network defaults

Add these options:

```nix
services.surmhosting.auth.network = {
  hostAddress = "10.202.0.1";
  localAddress = "10.202.0.2";
};
```

The auth container keeps the complete configured addresses.

For URLs, remove an optional CIDR suffix from the final evaluated local address.

The normalized address controls every forward-auth URL and the auth Traefik backend.

The host and local addresses must differ.

### 8.6 Internal OAuth endpoint seam

Add these internal auth module options:

```nix
services.surm-auth.github = {
  authUrl = null;
  tokenUrl = null;
  userUrl = null;
  usersApiUrl = null;
};
```

Use nullable string types.

Null values omit the matching fields from the rendered configuration.

The Go service then uses its public GitHub defaults.

The VM fixture sets local endpoints through `containers.surm-auth.config`.

Do not expose these values through the public `services.surmhosting` interface.

### 8.7 Container DNS defaults

Add this option:

```nix
services.surmhosting.network.nameservers = [ "8.8.8.8" ];
```

Surmhosting applies this value with `lib.mkDefault` to supplied workload containers.

The supplied container configuration can override it normally.

The option also controls the Surmhosting-owned auth container.

### 8.8 Native NAT overrides

Surmhosting keeps these current NAT defaults:

```nix
networking.nat.internalIPs = lib.mkDefault [
  "10.201.0.0/16"
  "10.202.0.0/16"
];
```

Do not add a duplicate Surmhosting NAT option.

A user with custom addresses overrides the native NixOS NAT option.

### 8.9 DNS challenge provider

Add this option:

```nix
services.surmhosting.tls.dnsProvider = "cloudflare";
```

The default preserves current behavior.

The consumer supplies the matching environment file.

### 8.10 Dashboard rule

Add this option:

```nix
services.surmhosting.dashboard.rule = "HostRegexp(`^dashboard\\.surmcluster`)";
```

The default preserves the current route.

### 8.11 Public firewall management

Add this option:

```nix
services.surmhosting.firewall.enable = true;
```

When enabled, Surmhosting sets `networking.firewall.enable` with `lib.mkDefault true`.

It opens port 80 and conditionally opens port 443.

It makes no other firewall change.

Citadel keeps its explicit `networking.firewall.enable = false` value.

## 9. Target Stage 1 layout

Stage 1 groups the known component files here:

```text
modules/services/surmhosting/
├── README.md
├── default.nix
├── nix/
│   ├── checks/
│   │   └── surm-auth-e2e.nix
│   ├── modules/
│   │   ├── surm-auth.nix
│   │   └── surmhosting.nix
│   └── packages/
│       └── surm-auth.nix
├── surm-auth/
│   ├── audit/
│   ├── auth/
│   ├── config/
│   ├── handlers/
│   ├── policy/
│   ├── templates/
│   ├── e2e_test.go
│   ├── go.mod
│   ├── go.sum
│   ├── main.go
│   └── main_test.go
└── tests/
    ├── auth-container.nix
    └── default.nix
```

`modules/services/surmhosting/default.nix` remains the stable local import path.

It returns the module from `nix/modules/surmhosting.nix`.

Stage 1 removes known nixenv coupling. Stage 1 does not claim exhaustive extraction isolation.

## 10. Nixenv outputs during Stage 1

Nixenv adds this module output:

```nix
flake.nixosModules.surmhosting = ./modules/services/surmhosting;
```

Nixenv keeps its current `packages.<system>.surm-auth` output during Stage 1.

Nixenv exposes these x86 Linux checks during Stage 1:

```nix
checks.x86_64-linux.surmhosting-module
checks.x86_64-linux.surm-auth-e2e
checks.x86_64-linux.surmhosting-auth-container
```

Stage 2 removes all these Surmhosting outputs from nixenv.

## 11. Stage 1 implementation tasks

### Task 1: Create the mechanical relocation commit

**Purpose:** Move files without changing effective host behavior.

**Files:**

- Move: `apps/surm-auth/**`
- Move: `modules/services/surm-auth/default.nix`
- Move: `modules/services/surmhosting/default.nix`
- Move: `modules/services/surmhosting/tests.nix`
- Move: `packages/surm-auth/default.nix`
- Move: `packages/surm-auth/e2e-check.nix`
- Create: `modules/services/surmhosting/default.nix`
- Create: `packages/surm-auth/default.nix`
- Modify: `pkgs/surm-auth/default.nix`
- Modify: `modules/core/checks.nix`
- Modify: `packages/update-all/update-all.nu`

**Step 1:** Start from the reviewed baseline.

Run:

```bash
git fetch origin main
git switch -c surmhosting-module origin/main
```

Do not run these commands when the existing approved branch already starts at the reviewed baseline.

**Step 2:** Evaluate the baseline Nexus and Citadel systems.

Force `system.configurationRevision` to one fixed comparison value.

Record both resulting derivation paths and their recursive `nix-diff` output.

The comparison must use baseline revision `17c48975634079e9bc43b8274eaacbdf5686cd22`.

**Step 3:** Move each canonical file with `git mv`.

Keep only the wrappers required by current nixenv import and package paths.

Apply only relative import changes that the moves require.

Do not remove `inputs`, pipe operators, machine imports, or hard-coded values in this commit.

**Step 4:** Update the package updater path.

It must read:

```text
modules/services/surmhosting/nix/packages/surm-auth.nix
```

**Step 5:** Stage every moved and newly created file before Nix evaluation.

Git flakes exclude untracked files.

**Step 6:** Inspect staged rename detection.

Run:

```bash
git diff --cached --summary --find-renames
git diff --cached --check
```

Expected result: Git recognizes the source, module, package, check, and test moves.

**Step 7:** Run the relocated focused tests and package build.

Expected result: Every command exits with status zero.

**Step 8:** Compare both host systems with the baseline.

Normalize `system.configurationRevision` before comparison.

Use `nix-diff` to inspect every changed derivation.

No evaluated service, route, container, mount, dependency, firewall, NAT, or Traefik value may change.

A source-path store identity can change. The review must record why that identity changed.

**Step 9:** Commit the mechanical relocation.

Run:

```bash
git commit --no-gpg-sign -m "refactor: relocate surmhosting component files"
```

### Task 2: Remove known nixenv coupling

**Purpose:** Make the component ready for the later standalone attempt.

**Files:**

- Modify: `modules/services/surmhosting/nix/modules/surmhosting.nix`
- Modify: `modules/services/surmhosting/nix/modules/surm-auth.nix`
- Modify: `modules/services/surmhosting/nix/packages/surm-auth.nix`
- Modify: `modules/services/surmhosting/nix/checks/surm-auth-e2e.nix`
- Modify: `modules/services/surmhosting/tests/default.nix`
- Modify: `packages/surm-auth/default.nix`
- Modify: `pkgs/surm-auth/default.nix`

**Step 1:** Remove `inputs` from both component module argument sets.

**Step 2:** Build the default auth package from the component-local package file.

The auth module must use `pkgs.callPackage` with the component-local source.

**Step 3:** Remove known `inputs.self.packages` references from the component.

**Step 4:** Make the package and end-to-end check use the relocated Go source.

**Step 5:** Make the module tests construct the local package directly.

**Step 6:** Remove Nexus machine imports from the component tests.

Replace those assertions with synthetic fixtures where they still test component behavior.

**Step 7:** Rewrite pipe-operator expressions with ordinary nested calls.

Preserve evaluation order and attribute ordering.

**Step 8:** Do not add an extraction-isolation check or coupling token search.

Stage 2 will expose unknown dependencies through standalone evaluation.

**Step 9:** Stage the exact changed paths.

Run the focused module and auth checks after staging.

**Step 10:** Evaluate the Nexus and Citadel system derivations.

Expected result: Both evaluations succeed.

**Step 11:** Commit the known coupling removal.

Run:

```bash
git commit --no-gpg-sign -m "refactor: remove known nixenv coupling from surmhosting"
```

### Task 3: Transfer auth state and secret ownership

**Files:**

- Modify: `modules/services/surmhosting/nix/modules/surmhosting.nix`
- Modify: `modules/services/surmhosting/nix/modules/surm-auth.nix`
- Modify: `modules/services/surmhosting/tests/default.nix`
- Modify: `machines/nexus/default.nix`
- Modify: `machines/nexus/service-surm-auth.nix`

**Step 1:** Add the auth and Traefik unit dependency options.

The default generated units must not name `secrets.service`.

Configured values must appear in the correct systemd dependency fields.

**Step 2:** Make each auth credential option control its real host mount.

Use `types.nullOr types.externalPath` in the public module.

Use `types.externalPath` for the required internal auth options.

Use three unrelated quoted runtime paths in the focused test.

Each host path must reach the matching fixed container path.

Assert that store-backed strings and Nix path literals fail option validation.

**Step 3:** Add nullable `auth.stateHostPath` without a default path.

Use `types.nullOr types.externalPath`.

Require a value only when auth is enabled.

Mount the value at `/var/lib/private` inside the auth container.

Do not create or modify the host path.

Test one accepted `/var/lib/...` string and one rejected store path.

**Step 4:** Remove state and credential directory creation from Surmhosting.

**Step 5:** Make Nexus own both directories.

Keep these paths and modes:

```text
/var/lib/surm-auth-state 0700 root root
/var/lib/surm-auth-credentials 0700 root root
```

Set the Nexus state path explicitly:

```nix
services.surmhosting.auth.stateHostPath = "/var/lib/surm-auth-state";
```

**Step 6:** Configure Nexus secret dependencies explicitly.

Use:

```nix
services.surmhosting.auth.unitDependencies = {
  requires = [ "secrets.service" ];
  after = [ "secrets.service" ];
};
```

Nexus currently uses HTTP-01. It needs no Traefik credential dependency.

**Step 7:** Stage the exact changed paths.

Run focused tests and both host evaluations after staging.

**Step 8:** Commit the ownership transfer.

Run:

```bash
git commit --no-gpg-sign -m "refactor: make surmhosting state and secrets consumer-owned"
```

### Task 4: Apply the network and firewall contract

**Files:**

- Modify: `modules/services/surmhosting/nix/modules/surmhosting.nix`
- Modify: `modules/services/surmhosting/tests/default.nix`
- Modify: `machines/nexus/default.nix`

**Step 1:** Keep generated service addresses as `lib.mkDefault` values.

Do not add `services.surmhosting.services.<name>.network` options.

**Step 2:** Make Traefik read each final evaluated container local address.

Keep this read outside the nested container configuration to avoid an evaluation cycle.

Accept a final IPv4 value with an optional CIDR suffix.

Strip the suffix only when constructing the Traefik URL.

Keep the complete value in `config.containers.<name>.localAddress`.

Assert that every exposed container has a non-null usable IPv4 local address.

Test an override such as `10.50.0.2/24`.

The container must retain `/24`, while Traefik must use `10.50.0.2`.

Test that an exposed container with a null local address fails clearly.

**Step 3:** Add configurable auth network values.

Read the final evaluated auth container local address for URL construction.

Normalize an optional CIDR suffix in the same way.

Use the normalized address in these places:

- Every generated `forwardAuth.address`
- The auth Traefik backend URL

Use the complete configured values for these container options:

- The auth container local address
- The auth container host address

**Step 4:** Add configurable DNS defaults.

Apply the default with `lib.mkDefault` to workload containers.

Apply the same configured value directly to the auth container.

**Step 5:** Apply NAT defaults through the native NixOS option.

Use `lib.mkDefault` for the current `10.201.0.0/16` and `10.202.0.0/16` ranges.

Do not add a second NAT option under Surmhosting.

**Step 6:** Add the DNS provider and dashboard rule options.

Keep the existing values as defaults.

**Step 7:** Limit Surmhosting firewall management to public ports.

Open port 80 when public HTTP exists.

Open port 443 only when TLS is enabled.

Remove the `ve-+` trusted-interface value.

Do not add any rule for `internalPort`.

**Step 8:** Leave the Nexus port 8081 rule in `machines/nexus/default.nix`.

Do not move or rewrite that rule.

Keep Citadel's explicit firewall disable value.

**Step 9:** Preserve Podman compatibility and Traefik Docker discovery.

Add focused assertions for these effective values:

- `virtualisation.podman.enable`
- `virtualisation.podman.dockerCompat`
- `virtualisation.podman.dockerSocket.enable`
- The Traefik `podman` group
- The Traefik Docker provider

**Step 10:** Stage the exact changed paths.

Run focused tests and both host evaluations after staging.

Inspect the expected removal of the ineffective `ve-+` rule separately.

**Step 11:** Commit the infrastructure contract.

Run:

```bash
git commit --no-gpg-sign -m "refactor: define surmhosting network and firewall ownership"
```

### Task 5: Export the local module and checks

**Files:**

- Modify: `flake.nix`
- Modify: `modules/core/checks.nix`
- Create: `modules/services/surmhosting/README.md`

**Step 1:** Export the named module.

Use:

```nix
flake.nixosModules.surmhosting = ./modules/services/surmhosting;
```

Do not assign `nixosModules.default` in nixenv.

**Step 2:** Export the focused module check as `surmhosting-module`.

**Step 3:** Export the component auth check as `surm-auth-e2e`.

**Step 4:** Keep the existing nixenv `surm-auth` package output during Stage 1.

**Step 5:** Write the component README.

Document these subjects:

- The module purpose
- Surmhosting-owned behavior
- Consumer-owned behavior
- A supplied NixOS container example
- A host backend example
- Generated defaults and normal NixOS overrides
- The bundled auth service
- User-owned external credential and state paths
- Public firewall behavior
- User-owned internal firewall behavior
- Optional OCI label discovery
- Every public option
- Stage 1 test commands

**Step 6:** Stage `flake.nix`, the check changes, and the new README.

Evaluate the named module directly after staging.

Then evaluate a minimal `nixosSystem` that imports the named module.

Do not use `nix flake show --all-systems` as the acceptance gate.

**Step 7:** Build all current focused checks.

**Step 8:** Commit the local public interface.

Run:

```bash
git commit --no-gpg-sign -m "feat: export the surmhosting module from nixenv"
```

### Task 6: Add the auth container runtime check

**Files:**

- Create: `modules/services/surmhosting/tests/auth-container.nix`
- Modify: `modules/services/surmhosting/nix/modules/surm-auth.nix`
- Modify: `modules/services/surmhosting/tests/default.nix`
- Modify: `modules/core/checks.nix`

**Step 1:** Add internal GitHub endpoint options to `services.surm-auth`.

Add nullable options for these endpoints:

- Authorization
- Token exchange
- Current user
- User lookup

Production defaults must remain null.

The rendered configuration must omit every null endpoint field.

Do not add matching options under public `services.surmhosting`.

**Step 2:** Add focused rendering tests.

Prove that production defaults omit all endpoint overrides.

Prove that configured local endpoints reach the four expected rendered fields.

**Step 3:** Create an x86 Linux NixOS virtual-machine test.

The fixture owns its synthetic credential files and auth state directory.

The fixture configures its setup unit through `auth.unitDependencies`.

The fixture adds its endpoint overrides through `containers.surm-auth.config`.

**Step 4:** Start the real bundled auth package inside the generated auth container.

Run the local OAuth mock on the isolated VM network.

The mock must implement authorization, token exchange, current-user, and user-lookup endpoints.

The VM must have no route to public GitHub or other production services.

**Step 5:** Prove these behaviors:

- Surmhosting starts Traefik.
- The auth container waits for the fixture setup unit.
- The auth process reads all three configured credential files.
- The health endpoint responds.
- The complete OAuth callback flow uses the local mock.
- Policy state survives auth container recreation.
- The generated auth configuration contains paths but no secret contents.
- Surmhosting does not create the host state directory.

**Step 6:** Export the check as `surmhosting-auth-container`.

Stage every changed file before any flake command.

**Step 7:** Build the check and commit it.

Run:

```bash
git commit --no-gpg-sign -m "test: verify the bundled surm-auth container"
```

### Task 7: Complete Stage 1 verification

**Step 1:** Verify Go formatting.

Run from `modules/services/surmhosting/surm-auth`:

```bash
nix shell --impure --expr \
  '(builtins.getFlake (toString ../../../..)).inputs.nixpkgs.legacyPackages.x86_64-linux.go' \
  -c sh -c 'test -z "$(gofmt -l .)"'
```

**Step 2:** Run Go static analysis.

Run:

```bash
nix shell --impure --expr \
  '(builtins.getFlake (toString ../../../..)).inputs.nixpkgs.legacyPackages.x86_64-linux.go' \
  -c env GOTOOLCHAIN=local go vet ./...
```

**Step 3:** Run Go race tests with a declared compiler.

Run:

```bash
nix shell --impure --expr \
  'let pkgs = (builtins.getFlake (toString ../../../..)).inputs.nixpkgs.legacyPackages.x86_64-linux; in [ pkgs.go pkgs.stdenv.cc ]' \
  -c env CGO_ENABLED=1 GOTOOLCHAIN=local go test -race ./...
```

**Step 4:** Build the auth package.

Run from the repository root:

```bash
nix build --no-link .#packages.x86_64-linux.surm-auth
```

**Step 5:** Build all three Stage 1 checks.

Run:

```bash
nix build --no-link \
  .#checks.x86_64-linux.surmhosting-module \
  .#checks.x86_64-linux.surm-auth-e2e \
  .#checks.x86_64-linux.surmhosting-auth-container
```

**Step 6:** Evaluate both active host systems.

Run:

```bash
nix eval --raw .#nixosConfigurations.nexus.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.citadel.config.system.build.toplevel.drvPath
```

**Step 7:** Confirm the firewall boundary.

Verify these values:

- Surmhosting opens only ports 80 and 443.
- Surmhosting adds no internal firewall rule.
- Nexus still owns its existing port 8081 rule.
- Citadel still disables its firewall explicitly.

**Step 8:** Confirm that OCI declarations remain unchanged.

Run:

```bash
git diff origin/main -- \
  machines/nexus/service-jellyfin.nix \
  machines/nexus/service-jaeger.nix
```

Expected result: The command prints no diff.

**Step 9:** Inspect the complete branch.

Run:

```bash
git status --short --branch
git diff origin/main --stat
git diff origin/main --check
```

**Step 10:** Record unrelated root failures separately.

The Darwin-only `handy` package can still block a complete Linux flake traversal.

The unrelated `testcontainer` output still lacks its module import and uses `serverExpose`.

**Step 11:** Push only after implementation approval.

Use:

```bash
git push -u origin surmhosting-module
```

Send this review link:

```text
https://github.com/surma/nixenv/compare/main...surmhosting-module
```

Stop after Stage 1. Wait for review and merge approval.

## 12. Stage 1 acceptance criteria

Stage 1 is complete only when every criterion below is true.

- All known component files live under `modules/services/surmhosting`.
- The mechanical relocation has no unexplained host behavior change.
- The component needs no nixenv `inputs` special argument.
- The component uses no Nix pipe operators.
- The root flake exports `nixosModules.surmhosting`.
- The root flake still exports the `surm-auth` package.
- Surmhosting enables and configures Traefik.
- Supplied container values override generated defaults normally.
- Traefik normalizes final evaluated container addresses for URL use.
- Exposed containers cannot use a null local address.
- Surmhosting opens only its public firewall ports.
- Nexus keeps ownership of its port 8081 rule.
- Surmhosting bundles and runs auth when auth is enabled.
- Surmhosting names no secret-manager unit by default.
- Configured credential paths control the real auth mounts.
- Runtime state and credential options reject Nix store paths.
- The user owns and prepares the auth state path.
- The offline auth check uses explicit local OAuth endpoints.
- Production auth configuration omits endpoint overrides.
- Consumer workload bind mounts remain untouched.
- Podman and Traefik Docker discovery retain their current behavior.
- Jellyfin and Jaeger declarations remain untouched.
- The focused checks pass.
- Nexus and Citadel evaluate successfully.
- No host receives a deployment.

Stage 1 does not assert that the component already works outside nixenv.

## 13. Stage 2 decisions required before work

Stage 2 starts only after Stage 1 merges.

The user must confirm these values before repository creation:

- The local repository path
- The remote repository URL
- The repository visibility
- The license
- The supported NixOS release
- The CI provider, if any
- The final Go module path

The likely initial remote is a private Gitea repository.

The repository starts with fresh history. No nixenv commit enters the new repository.

The standalone flake supports these systems:

- `x86_64-linux`, with build and runtime checks
- `aarch64-linux`, with evaluation-only checks

A release tag is outside this plan.

## 14. Target Stage 2 layout

The new repository uses this layout:

```text
surmhosting/
├── examples/
│   └── minimal.nix
├── nix/
│   ├── checks/
│   │   └── surm-auth-e2e.nix
│   ├── modules/
│   │   ├── surm-auth.nix
│   │   └── surmhosting.nix
│   └── packages/
│       └── surm-auth.nix
├── surm-auth/
│   └── ...
├── tests/
│   ├── auth-container.nix
│   └── default.nix
├── default.nix
├── flake.lock
├── flake.nix
├── LICENSE
└── README.md
```

An approved CI file can join this layout later in Stage 2.

The standalone flake exports these values:

```nix
nixosModules.default
nixosModules.surmhosting
packages.x86_64-linux.surm-auth
packages.aarch64-linux.surm-auth
checks.x86_64-linux.surmhosting-module
checks.x86_64-linux.surm-auth-e2e
checks.x86_64-linux.surmhosting-auth-container
```

`nixosModules.default` and `nixosModules.surmhosting` point to the same module.

The auth module remains an internal implementation detail.

## 15. Stage 2 implementation tasks

### Task 8: Create the fresh standalone repository

**Step 1:** Obtain explicit Stage 2 approval.

State the exact local path before any write outside the current working directory.

Repository creation and remote publication need separate approval.

**Step 2:** Start from the merged Stage 1 `origin/main` revision.

Use a clean nixenv checkout.

**Step 3:** Copy the contents of `modules/services/surmhosting` into the approved repository root.

Do not copy nixenv's `.git` directory or commit history.

**Step 4:** Initialize fresh Git history on a feature branch.

Use `--no-gpg-sign` for every commit.

Do not add or push a remote without approval.

### Task 9: Add the standalone flake and documentation

**Files:**

- Create: `flake.nix`
- Create: `flake.lock`
- Create: `LICENSE`
- Modify: `README.md`
- Create: `examples/minimal.nix`

**Step 1:** Add only the approved Nixpkgs input.

**Step 2:** Export both module aliases.

Use:

```nix
nixosModules = {
  default = import ./default.nix;
  surmhosting = self.nixosModules.default;
};
```

**Step 3:** Export the auth package for x86 Linux and ARM Linux.

**Step 4:** Export the three checks for x86 Linux.

Do not claim native ARM test coverage.

**Step 5:** Add a minimal supplied-container example.

The example must show normal NixOS overrides inside the supplied container configuration.

The example must state that users own internal and service-to-service firewall rules.

**Step 6:** Document optional OCI discovery.

Do not claim that Surmhosting owns OCI declarations or labels.

**Step 7:** Add the approved license.

**Step 8:** Update package metadata for the approved repository URL.

**Step 9:** Update the Go module path in a separate commit when the final repository URL is known.

Run `go mod tidy` with the pinned Go toolchain.

Do not change third-party versions without a separate reason.

### Task 10: Add approved CI

Skip this task when Stage 2 approval names no CI provider.

**Step 1:** Build and test x86 Linux.

Run these checks:

- `nix flake check`
- The x86 auth package build
- Go formatting
- Go vet
- Go race tests with a C compiler

**Step 2:** Evaluate ARM Linux outputs without a native build requirement.

**Step 3:** Pin every CI action or reusable dependency.

**Step 4:** Keep CI free of production credentials.

### Task 11: Verify the standalone repository

**Step 1:** Stage every new standalone file.

Git flakes exclude untracked files.

Run:

```bash
nix flake show
nix flake check
nix build --no-link .#packages.x86_64-linux.surm-auth
nix eval --raw .#packages.aarch64-linux.surm-auth.drvPath
```

Expected result: Every command exits with status zero.

The ARM command proves evaluation only.

**Step 2:** Evaluate the documented example through `nixpkgs.lib.nixosSystem`.

Do not pass a custom `inputs` argument.

**Step 3:** Treat standalone evaluation failures as Stage 2 extraction defects.

Fix each real dependency in the standalone repository.

Do not add a separate extraction-isolation test.

**Step 4:** Inspect the complete diff and Git status.

**Step 5:** Commit on the approved feature branch.

**Step 6:** Stop before remote creation or push unless the user separately approves them.

### Task 12: Consume the external flake from nixenv

**Files:**

- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `machines/nexus/default.nix`
- Modify: `machines/citadel/default.nix`
- Modify: `machines/nexus/service-scout.nix`
- Modify: `modules/core/checks.nix`
- Modify: `modules/core/packages.nix` only if Stage 1 added a special entry
- Modify: `packages/update-all/update-all.nu`
- Remove after verification: `modules/services/surmhosting/**`
- Remove after verification: `packages/surm-auth/**`
- Remove after verification: `pkgs/surm-auth/**`

**Step 1:** Start a new nixenv branch from the latest `origin/main`.

Stage 1 must already exist through its merge.

**Step 2:** Add the approved external flake input.

Make its Nixpkgs input follow nixenv's Nixpkgs input.

Pin the reviewed external revision in `flake.lock`.

**Step 3:** Replace local Surmhosting imports on Nexus and Citadel.

Use:

```nix
inputs.surmhosting.nixosModules.default
```

**Step 4:** Remove Surmhosting outputs from nixenv.

Remove these outputs and aliases:

- `nixosModules.surmhosting`
- `packages.<system>.surm-auth`
- `checks.<system>.surmhosting-module`
- `checks.<system>.surm-auth-e2e`
- `checks.<system>.surmhosting-auth-container`

Nixenv must not mirror standalone package or component check outputs.

**Step 5:** Remove the auth entry from the nixenv package updater.

Update comments that name the old local module path in `machines/nexus/service-scout.nix`.

**Step 6:** Evaluate Nexus and Citadel before local file removal.

Expected result: Both hosts use the pinned external module successfully.

**Step 7:** Obtain explicit approval for local implementation removal.

List every path before removal.

**Step 8:** Remove the local component and compatibility wrappers.

**Step 9:** Evaluate both hosts again.

**Step 10:** Commit with `--no-gpg-sign` and inspect the complete diff.

### Task 13: Complete Stage 2 verification

**Step 1:** Run all standalone x86 checks.

**Step 2:** Evaluate the standalone ARM package and module outputs.

**Step 3:** Evaluate Nexus and Citadel from nixenv.

**Step 4:** Confirm these migration invariants:

- Both hosts use one pinned external revision.
- Container names and final addresses remain unchanged.
- Generated Traefik configuration remains unchanged.
- Public firewall behavior remains unchanged.
- Nexus keeps its host-owned port 8081 rule.
- Auth policy and credential paths remain unchanged.
- Production state paths remain unchanged.
- Jellyfin and Jaeger declarations remain unchanged.

**Step 5:** Inspect both repository diffs.

**Step 6:** Push either repository only after its separate approval.

**Step 7:** Send separate review links when remotes exist.

**Step 8:** Stop before merge or deployment.

## 16. Stage 2 acceptance criteria

Stage 2 is complete only when every criterion below is true.

- A fresh standalone repository exists at the approved location.
- The repository contains no imported nixenv Git history.
- The repository contains the approved license.
- `nix flake check` passes on x86 Linux.
- The x86 auth package builds.
- The ARM package and module outputs evaluate.
- The flake exposes the documented modules, packages, and checks.
- The documented example evaluates without custom special arguments.
- Nixenv consumes one pinned external revision.
- Nixenv exposes no Surmhosting module, package, or component check outputs.
- No local Surmhosting implementation remains in nixenv.
- Nexus keeps its host-owned internal firewall rule.
- No production state moves or changes ownership.
- No production host receives a deployment.

## 17. Known limitations

Stage 1 does not prove standalone extraction. Stage 2 standalone evaluation provides that feedback.

ARM Linux receives evaluation-only coverage until native ARM CI exists.

Generated service addresses still depend on lexical service order by default.

Users who override container networks must also override native NixOS NAT settings when necessary.

Surmhosting does not manage port 8081 or other service-to-service access.

The current auth module retains legacy version-1 rendering. Legacy cleanup requires a separate behavior change.

The root nixenv flake can still fail on Linux while it evaluates the Darwin-only `handy` package.

The unrelated `testcontainer` output still lacks its module import and uses `serverExpose`.

## 18. Review gates

### Gate A: Approve Stage 1 implementation

Confirm these points:

- Stage 1 starts with a behavior-preserving relocation commit.
- Later changes use separate commits.
- Surmhosting manages only public firewall ports.
- Nexus owns its port 8081 rule.
- Supplied container values override Surmhosting defaults normally.
- Traefik strips CIDR suffixes from final addresses used in URLs.
- Runtime state and credential paths stay outside the Nix store.
- Users own auth state and credential host paths.
- The auth VM uses internal local OAuth endpoint overrides.
- Stage 1 includes no extraction-isolation test.

### Gate B: Review Stage 1

Review the nixenv compare link, focused checks, host evaluations, and explained relocation differences.

Merge only after that review passes.

### Gate C: Approve Stage 2 metadata

Confirm the repository path, remote, visibility, license, NixOS release, CI provider, and Go module path.

### Gate D: Approve repository actions

Approve repository creation, remote creation, and push as separate actions when required.

### Gate E: Approve local removal

Approve local implementation removal only after both hosts consume the external module successfully.

### Gate F: Approve deployment

A code merge does not authorize deployment.

Any Nexus or Citadel deployment needs a new request with the exact host and flake reference.
