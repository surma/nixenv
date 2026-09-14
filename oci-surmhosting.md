# OCI Surmhosting Implementation Plan

**Goal:** Add a first-class rootful Podman backend to Surmhosting.

**Architecture:** Each service selects one explicit backend. The existing exposure and authentication code consumes a backend-neutral endpoint. The Podman backend creates one private `/30` bridge network per service, assigns a stable container address, and sends Traefik directly to that address.

**Tech Stack:** NixOS modules, rootful Podman, Netavark, nftables, systemd, Traefik, and Nix evaluation fixtures.

---

## 1. Scope and decisions

This plan covers the Surmhosting module and its managed service declarations. It migrates configuration syntax, but it does not convert an existing service to Podman or deploy a host.

The implementation makes these decisions:

1. The public backend namespace contains `host`, `nixos-container`, and `podman`.
2. A service selects exactly one backend.
3. `backend.podman` means rootful Podman managed by the NixOS OCI module.
4. Surmhosting enables Podman automatically when a Podman backend exists.
5. The module creates one private Podman bridge network per Podman service.
6. The module assigns a fixed container address inside that network.
7. Traefik sends requests to the fixed container address.
8. The Podman backend may publish additional ports when a service declares them explicitly.
9. The module keeps the current NixOS-container endpoint contract.
10. The module removes `host`, `container`, `containerName`, and `containerService`.
11. The implementation migrates every repository consumer to the new backend namespace in the same completed change.
12. The module does not provide a compatibility adapter for the removed options.

The design does not support rootless Podman. Rootless networking does not provide the required host-to-container address contract.

The design does not create one shared Podman network for all services. Per-service networks provide deterministic addressing and separate network state. They are not a security boundary. The current NixOS-container topology also permits routed traffic through the host.

The design does not reproduce the current NixOS-container network at the kernel level. NixOS containers use a veth pair, `/32` addresses, and explicit routes. Podman uses a bridge, a gateway, and a `/30` network.

## 2. Current repository state

The primary implementation file is `modules/services/surmhosting/default.nix`.

The focused evaluation fixtures live in `modules/services/surmhosting/tests.nix`.

The current service options include these backend fields:

```nix
services.surmhosting.services.<name>.host
services.surmhosting.services.<name>.container
services.surmhosting.services.<name>.containerName
services.surmhosting.services.<name>.containerService
```

The current module derives these NixOS-container addresses:

```text
container address: 10.201.<service-index>.2
host address:      10.201.<service-index>.1
```

The current authentication container uses this address pair:

```text
auth container address: 10.202.0.2
auth host address:      10.202.0.1
```

The current NAT configuration owns the `10.201.0.0/16` and `10.202.0.0/16` ranges.

The new Podman backend must use a separate default pool. The initial pool is `10.203.0.0/16`.

The host already uses Podman for several services. `machines/nexus/default.nix` sets the global OCI backend to Podman. `machines/nexus/service-jellyfin.nix` and `machines/nexus/service-jaeger.nix` use raw OCI declarations outside Surmhosting.

The first implementation must not silently change those raw OCI services. The global Podman setting must remain until a separate migration removes every raw OCI declaration.

## 3. Public configuration contract

### 3.1 New backend forms

The target configuration uses one of these forms:

```nix
services.surmhosting.services.admin = {
  backend.host = "localhost";

  expose.port = 8092;
};
```

```nix
services.surmhosting.services.app = {
  backend."nixos-container" = {
    name = "app";

    service = {
      wants = [ "secrets.service" ];
      requires = [ "secrets.service" ];
      after = [ "secrets.service" ];
      serviceConfig.MemoryMax = "8G";
    };

    config = {
      system.stateVersion = "25.05";
      services.example.enable = true;
    };
  };

  expose.apps.example = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    ports = [
      {
        port = 8080;
        hostname = "example";
      }
    ];
  };
};
```

```nix
services.surmhosting.services.app = {
  backend.podman = {
    image = "ghcr.io/example/app:1.2.3";
    imageFile = null;
    imageStream = null;
    pull = "missing";

    environment = {
      APP_PORT = "8080";
    };
    environmentFiles = [ ];
    volumes = [
      "/var/lib/example:/var/lib/example"
    ];
    devices = [ ];
    capabilities = { };
    privileged = false;
    user = null;
    workdir = null;
    entrypoint = null;
    cmd = [ ];
    hostname = null;

    podman.sdnotify = "conmon";

    service = {
      wants = [ "secrets.service" ];
      requires = [ "secrets.service" ];
      after = [ "secrets.service" ];
      serviceConfig.MemoryMax = "4G";
    };
  };

  expose.apps.example = {
    access.mode = "public";
    internal.access = "trusted-network";
    ports = [
      {
        port = 8080;
        hostname = "example";
      }
    ];
  };
};
```

The Podman service declaration uses the option names from `virtualisation.oci-containers`. Surmhosting owns the network, fixed IP, systemd service name, and Docker-provider opt-out label.

The Podman backend accepts explicit published ports through the upstream `ports` option. Published ports create direct host bindings outside Traefik and SurmAuth, subject to the host firewall. The generated HTTP exposure still uses the private container address.

Every Podman declaration must set `image`. `imageFile` and `imageStream` are optional load sources, and at most one may be set. A loaded image name and tag must match `image` so the runtime does not pull a different image.

The image must listen on `0.0.0.0` inside the container. An image that listens only on `127.0.0.1` cannot receive traffic through the bridge.

Use the upstream `conmon` notification mode unless the image defines a healthcheck. The `healthy` mode requires image healthcheck metadata.

### 3.2 Backend option rules

Add a `backend` namespace to `serviceConfig` in `modules/services/surmhosting/default.nix`.

Use these option shapes:

- `backend.host`: a nullable string target address.
- `backend."nixos-container"`: a nullable attribute set that mirrors the current NixOS-container payload.
- `backend.podman`: a nullable attribute set that mirrors the supported OCI payload.

Reserve these keys inside the managed backend attribute sets:

- `name` for the NixOS-container name.
- `service` for host systemd dependency overrides.
- `networkSlot` for an optional Podman address slot.

The NixOS backend must preserve the current fields such as `config`, `bindMounts`, `allowedDevices`, `additionalCapabilities`, `privateUsers`, `enableTun`, `forwardPorts`, and other NixOS-container options.

The Podman backend must preserve the supported OCI fields: `image`, `imageFile`, `imageStream`, `pull`, `login`, `cmd`, `entrypoint`, `environment`, `environmentFiles`, `volumes`, `ports`, `labels`, `log-driver`, `workdir`, `dependsOn`, `hostname`, `capabilities`, `devices`, `privileged`, `autoStart`, `autoRemoveOnStop`, `extraOptions`, and `podman.sdnotify`.

Surmhosting must reject these user-supplied Podman fields and values:

- `serviceName`, because Surmhosting generates the systemd service name.
- `networks`, because Surmhosting owns the private network.
- `podman.user`, because Surmhosting always runs Podman as root.
- `preRunExtraOptions`, because they can select another Podman connection or storage root.
- `labels."traefik.enable"`, because Surmhosting forces this label to `"false"`.
- `extraOptions` that set or change `--name`, `--network`, or `--ip` in either split or joined form.

Published-port options such as `-p`, `--publish`, and `--publish-all` are permitted. Prefer the typed `ports` option because it states the direct exposure clearly.

Every supported value must reach the generated `virtualisation.oci-containers` declaration without silent omission. Do not claim support for unspecified upstream options.

### 3.3 Backend selection

Create one internal backend resolver. Do not duplicate backend selection in the Traefik and systemd code paths.

The resolver must produce one normalized record with these fields:

```nix
{
  kind = "host" | "nixos-container" | "podman";
  endpointHost = "...";
  endpointPort = null;
  runtimeUnit = "...";
  serviceDependencies = {
    wants = [ ];
    requires = [ ];
    after = [ ];
    serviceConfig = { };
  };
}
```

The endpoint port stays inside each exposure declaration. The endpoint host comes from the backend.

The resolver must enforce these rules:

- Every service must set exactly one backend.
- A NixOS backend must contain a valid NixOS module configuration.
- A Podman backend must contain a non-empty `image` string.
- A Podman backend may set at most one of `imageFile` and `imageStream`.
- A host backend must contain a non-empty address.
- `useTargetHost` is valid only for a host backend.
- A service cannot use a Podman network slot that another Podman service uses.

There is no implicit localhost backend. Every repository consumer must declare `backend.host`, `backend."nixos-container"`, or `backend.podman` explicitly.

## 4. Breaking repository migration

This repository is the only current Surmhosting consumer. Remove the legacy backend options instead of implementing a compatibility layer.

Remove these options from `serviceConfig`:

```nix
host
container
containerName
containerService
```

Migrate every repository declaration in the same completed change:

- Move `host` to `backend.host`.
- Move `container` to `backend."nixos-container"`.
- Move `containerName` to `backend."nixos-container".name`.
- Move `containerService` to `backend."nixos-container".service`.
- Add `backend.host = "localhost"` where a service currently relies on the implicit default.

Do not add deprecation warnings, compatibility resolution, or legacy fixtures. NixOS generations are atomic, so the completed module and consumer migration deploy together.

## 5. Backend-neutral endpoint integration

Refactor `managedServiceConfigs` in `modules/services/surmhosting/default.nix`.

Replace the current `hasContainer`, `localAddress`, `hostAddress`, and `forwardHost` branch with the normalized backend record.

Keep these routing behaviors unchanged:

- Legacy routers use the normalized backend host.
- Logical app routers use the normalized backend host.
- Auth middleware continues to target `http://10.202.0.2:8080`.
- Host-header rewriting applies only to host backends.
- Internal and public router policy stays independent of the backend type.
- The generated Traefik service URL remains `http://<endpointHost>:<port>`.

The endpoint resolver must run before the code builds `legacyTraefikConfigs` and `appTraefikConfigs`.

The route code must not inspect `backend.podman`, `backend."nixos-container"`, or legacy fields directly after this refactor.

Add a fixture that declares one host backend, one NixOS backend, and one Podman backend. Assert that all three produce the same Traefik service shape with different endpoint addresses.

## 6. NixOS-container backend adapter

Move the current NixOS-container generation behind the normalized backend record.

Keep these current defaults:

```nix
privateNetwork = true;
ephemeral = true;
autoStart = true;
```

Keep the current order-dependent NixOS address scheme:

```text
localAddress = 10.201.<service-index>.2
hostAddress  = 10.201.<service-index>.1
```

The generated container addresses and Traefik targets use the same ordered service list, so they remain synchronized. Preserve the current service names and address map during this refactor. Some container configurations contain literal `10.201.<service-index>.1` host addresses. Internal DNS can replace those literals in separate follow-up work.

Set the normalized endpoint to the container address.

Set the normalized runtime unit to `container@<container-name>`.

Apply `backend."nixos-container".service` to the generated template unit. Preserve the existing top-level `Requires=`, `Wants=`, and `After=` behavior.

Apply the existing memory limits to NixOS-container units. Update the comments from `container@lc-*` to managed runtime units where the comment now covers both backends.

Reject user overrides for `privateNetwork`, `localAddress`, and `hostAddress` when Surmhosting manages the NixOS-container network. The backend owns these values so Traefik cannot receive a stale address.

Preserve user-controlled container features such as bind mounts, devices, capabilities, and in-container NixOS services.

Add regression assertions for the existing container unit and endpoint behavior before migrating repository consumers.

## 7. Podman backend adapter

Add the Podman backend to `modules/services/surmhosting/default.nix`.

Detect whether at least one normalized backend has `kind = "podman"`.

When a Podman backend exists, set these NixOS options:

```nix
virtualisation.podman.enable = true;
virtualisation.oci-containers.backend = lib.mkDefault "podman";
```

Do not force the global OCI backend over an explicit user value. Add an assertion that rejects a Podman Surmhosting backend when the final OCI backend is not Podman.

Do not enable Docker compatibility or the Docker socket from the Podman backend. Keep `services.surmhosting.docker.enable` responsible for the existing Traefik Docker provider contract.

Generate one internal OCI container name per service:

```text
surmhosting-<service-name>
```

Generate one systemd service name per service:

```text
surmhosting-podman-<service-name>.service
```

Generate the NixOS OCI declaration with these managed values:

```nix
{
  serviceName = "surmhosting-podman-<service-name>";
  networks = [ "surmhosting-<service-name>" ];
  extraOptions = [ "--ip=<fixed-container-address>" ] ++ userExtraOptions;
  ports = userPorts;
  labels = userLabels // {
    "traefik.enable" = "false";
  };
  podman.user = "root";
}
```

The forced `traefik.enable=false` label opts the managed container out of Traefik Docker-provider discovery. Surmhosting exposes the container only through its generated file-provider route. Keep the global Docker provider unchanged for independent containers, including Jellyfin and Jaeger.

Merge supported user OCI values only after validating reserved fields. Reject conflicts instead of ignoring them.

Map `backend.podman.service` to the generated systemd service. Add the global memory limits to that unit.

Map user `dependsOn` service names to generated internal OCI container names. Reject dependencies on a host backend or a NixOS-container backend.

Keep the default journald log driver. This preserves the current systemd journal workflow.

Use rootful Podman even when the image process uses a non-root `user` value. The image user and the Podman systemd user have different meanings.

## 8. Private Podman network allocation

Add the following options under `services.surmhosting.podman`:

```nix
networkPrefix = "10.203";
```

Use `10.203` as the default prefix. Document that the prefix must not overlap a host, LAN, VPN, Tailscale, or container route.

Add an optional `networkSlot` field to `backend.podman`. Accept integer values from `1` through `254`.

When `networkSlot` is null, derive the slot from a stable hash of the logical service name. Use the first hash byte modulo `254`, then add `1`.

Assert that all Podman services have unique slots after applying explicit overrides and hash-derived values. A collision must name both services and instruct the user to set an explicit slot. This deterministic allocation with an explicit override is sufficient for the current scale.

Derive the network addresses as follows:

```text
network:          <prefix>.<slot>.0/30
host gateway:     <prefix>.<slot>.1
container:        <prefix>.<slot>.2
broadcast:        <prefix>.<slot>.3
```

Use the host gateway as the bridge address. Use the container address as the fixed Podman address.

Use the logical service name in the network name. Do not use the hash as the network name because operators need readable runtime state.

Add assertions for these network conditions:

- The service name produces a valid Podman network name.
- The slot stays within `1..254`.
- Both prefix octets are integers from `0` through `255`.
- The prefix does not overlap the managed `10.201.0.0/16` or `10.202.0.0/16` ranges.
- No two managed Podman services share a subnet.
- The Podman backend does not request an alternate network mode.

Keep the Podman pool separate from `10.201.0.0/16` and `10.202.0.0/16`.

## 9. Runtime network lifecycle

Nix evaluation cannot create a live Podman network. Generate one idempotent network script per Podman service and run it before every container start.

Attach the script to the generated OCI service as the first `ExecStartPre` command. Use `lib.mkBefore` so it runs before the OCI module loads the image and starts the container. Do not use a `RemainAfterExit` oneshot as the only check because an active oneshot does not run again on a later container restart.

The script must:

1. Test whether the named network exists.
2. Create it when it does not exist.
3. Use the bridge driver.
4. Use the computed `/30` subnet.
5. Use the computed host gateway.
6. Add ownership labels.
7. Inspect and verify the resulting network.
8. Fail when an existing network has a different driver, subnet, gateway, or ownership label.

Do not automatically delete or recreate a mismatched network. A replacement can disconnect a live service. Require an operator to stop the service and remove the network manually.

Use a generated script similar to this implementation:

```sh
#!/bin/sh
set -eu

network="$1"
subnet="$2"
gateway="$3"
service="$4"

if ! podman network exists "$network"; then
  podman network create \
    --driver bridge \
    --subnet "$subnet" \
    --gateway "$gateway" \
    --label "io.surmhosting.managed=true" \
    --label "io.surmhosting.service=$service" \
    "$network"
fi

podman network inspect "$network" \
  | jq -e \
      --arg subnet "$subnet" \
      --arg gateway "$gateway" \
      --arg service "$service" \
      '.[0]
       | .driver == "bridge"
       and any(.subnets[]?; .subnet == $subnet and .gateway == $gateway)
       and (.labels["io.surmhosting.managed"] // "false") == "true"
       and (.labels["io.surmhosting.service"] // "") == $service' \
  >/dev/null
```

Build the script with `pkgs.writeShellApplication`. Include Podman and `jq` as runtime inputs so the service does not depend on an ambient shell path.

A network creation or verification failure must prevent the container from starting. If an operator removes a valid unused network, the next container start must recreate it.

Do not remove old networks automatically when a service disappears from Nix configuration. Document manual cleanup as a separate operator action that requires confirmation.

## 10. Firewall, trust, and outbound networking

Keep NixOS-container NAT ownership for `10.201.0.0/16` and `10.202.0.0/16`.

Let Netavark own masquerading for the Podman bridge networks. Do not add `10.203.0.0/16` to `networking.nat.internalIPs` unless the runtime test proves that Netavark does not provide egress.

The locked NixOS Podman module selects Netavark and its nftables firewall driver when nftables is enabled. Assert the effective configuration instead of duplicating that integration.

Treat managed containers as trusted service peers. The current NixOS containers use private namespaces and point-to-point veth links, but host forwarding permits traffic between their routed addresses. The Podman backend does not introduce a stronger cross-service isolation guarantee.

The Nexus internal Traefik rule intentionally accepts `10.0.0.0/8` sources on port `8081`. The default `10.203.0.0/16` Podman pool therefore receives the same internal-route access as the current `10.201.0.0/16` containers.

Do not add a pool-wide rule that accepts every host port automatically. A host must grant any additional guest-to-host access through its normal firewall policy. Do not trust every dynamic Podman interface by name because unrelated host services may use Podman networks.

Add runtime checks for these paths:

- Host to container HTTP traffic.
- Container to the host gateway.
- Container to the internal Traefik entrypoint when the host policy permits it.
- Container to an external test endpoint through Netavark NAT.
- One managed service to another through the internal Traefik route.

## 11. Traefik and authentication behavior

Add only this managed Traefik label to every Surmhosting OCI container:

```nix
labels."traefik.enable" = "false";
```

The host may keep `providers.docker.exposedByDefault = true` for independently managed containers. The forced label opts out only the Surmhosting container. Do not generate Docker-provider routing labels for managed Surmhosting routes.

The file-provider configuration generated by Surmhosting remains the single route source for managed services.

Keep these existing route rules unchanged:

- Public routes use the public entrypoint.
- Internal routes use the internal entrypoint.
- Restricted apps use the app-specific forward-auth middleware.
- The middleware address remains the private auth-container address.
- Public domains remain derived from the logical app key.

Add a fixture that compares a host backend and a Podman backend with identical `expose.apps` declarations. Assert that only the load-balancer target differs.

Add an assertion that a Podman backend cannot use `expose.useTargetHost`. Podman routing must use its private address and does not need a Host rewrite.

Do not migrate `machines/nexus/service-jellyfin.nix` in the initial implementation. Its current Docker-provider route is internal-only, and the current logical-app API always derives a public route under `appsNamespace`. Migrate it only after the access policy receives a separate decision.

Do not migrate `machines/nexus/service-jaeger.nix` in the initial implementation. Its published OTLP port can pass through, but its internal-only HTTP route still needs a separate access-policy decision.

## 12. Focused evaluation tests

Modify `modules/services/surmhosting/tests.nix`.

Add these fixtures:

### 12.1 Host backend fixture

Declare:

```nix
backend.host = "localhost";
```

Assert that the generated Traefik target is `http://localhost:<port>`.

### 12.2 NixOS-container backend fixture

Declare a minimal `backend."nixos-container"` configuration.

Assert these values:

- The generated container exists.
- The generated container uses `privateNetwork = true`.
- The generated container uses the existing `10.201.*.2` endpoint.
- The generated systemd unit receives top-level dependency keys.
- The generated Traefik target uses the container address.

### 12.3 Podman backend fixture

Declare a minimal image string, one explicitly published port, and one logical app.

Assert these values:

- `virtualisation.podman.enable` is true.
- `virtualisation.oci-containers.backend` is `podman`.
- The internal OCI container name has the `surmhosting-` prefix.
- The generated service name has the `surmhosting-podman-` prefix.
- The container attaches to the generated private network.
- The generated command contains the fixed `--ip` value.
- The explicit published port reaches the generated OCI declaration unchanged.
- The generated labels force `traefik.enable` to `false`.
- The generated Traefik target uses the fixed Podman address.
- The generated `ExecStartPre` contains the expected subnet and gateway checks.
- The network check precedes the OCI module pre-start command.
- The Podman unit receives the configured memory limit.

### 12.4 Podman validation fixtures

Add invalid cases for these declarations:

- A missing or empty `image`.
- Simultaneous `imageFile` and `imageStream` values.
- User-supplied `podman.user`.
- User-supplied `networks`.
- User-supplied `labels."traefik.enable"`.
- User-supplied `--network` in split or joined form.
- User-supplied `--ip` in split or joined form.
- User-supplied `--name` in split or joined form.
- Conflicting `networkSlot` values.
- Invalid `networkSlot` values.
- Invalid service names.
- Podman backend combined with `useTargetHost = true`.
- Podman backend combined with OCI backend `docker`.

Assert that every failure names the offending service and option.

### 12.5 Migration and regression fixtures

Migrate every existing fixture to an explicit backend. Do not retain compatibility fixtures for removed backend options.

Add one negative evaluation that proves a removed backend option is unknown. Keep the existing authentication, routing, and systemd dependency behavior unchanged except for the new backend syntax.

Assert that adding Podman support does not change the current NixOS-container address map. Add a fixture for an explicit published Podman port and another fixture without published ports.

Run the focused suite with:

```sh
nix build --offline --no-write-lock-file --no-link --print-out-paths -L --impure \
  --expr '
    let
      f = builtins.getFlake ("git+file://" + toString ./.);
      pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      tests = import ./modules/services/surmhosting/tests.nix {
        inherit pkgs;
        inputs = f.inputs // { self = f; };
      };
    in
      tests.all
  '
```

Expected result:

```text
/nix/store/<hash>-surmhosting-focused-tests
```

## 13. Runtime Podman test

Create `modules/services/surmhosting/oci-vm-test.nix`.

Use `pkgs.testers.runNixOSTest` with a Surmhosting machine and a second machine that acts as an external endpoint. Import the real Surmhosting module. Do not reproduce backend logic inside the test.

Build a small local OCI image with `pkgs.dockerTools.buildImage`. Name the image explicitly, run a simple HTTP server on port `8080`, and bind it to `0.0.0.0`.

Set the same image name in `backend.podman.image`, pass the result through `imageFile`, and set `pull = "never"`. This proves the image load contract without registry access.

Configure one unauthenticated single-port HTTP route for the test. Keep TLS and authentication out of this runtime test because the test targets networking. Enable the existing Docker provider in the fixture so the test can prove that the forced opt-out label prevents automatic discovery.

The VM test must verify:

1. The Podman network is created when absent.
2. The network uses the expected `/30` subnet.
3. The network gateway uses the expected `.1` address.
4. The container uses the expected `.2` address.
5. The container has `traefik.enable=false`.
6. A service without `ports` has no published host port.
7. An explicitly configured published port works.
8. The host reaches the container address directly.
9. Traefik reaches the container through the generated file-provider route.
10. The Docker provider does not create a route for the managed container.
11. The container reaches the host gateway.
12. The container reaches the second machine through Netavark NAT.
13. A second managed service reaches the first through its host Traefik route.
14. Restarting the Podman service does not change the container address.
15. Removing an unused network causes the next service start to recreate it.
16. An existing network with the wrong subnet or gateway prevents service startup.
17. Container output appears in the systemd journal.

Export the VM test from `modules/services/surmhosting/tests.nix` as `ociRuntime`. Do not include the VM test in `tests.all` if that would make every focused evaluation build a VM.

Run the runtime test with:

```sh
nix build --no-link --print-out-paths --impure \
  --expr '
    let
      f = builtins.getFlake ("git+file://" + toString ./.);
      pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      tests = import ./modules/services/surmhosting/tests.nix {
        inherit pkgs;
        inputs = f.inputs // { self = f; };
      };
    in
      tests.ociRuntime
  '
```

Expected result:

```text
/nix/store/<hash>-nixos-test-oci-surmhosting
```

## 14. Repository consumer migration

Migrate all repository declarations to the explicit backend namespace in the same completed change that removes the old options.

Use this mechanical mapping:

```nix
host = "...";
```

becomes:

```nix
backend.host = "...";
```

Move each NixOS-container payload under `backend."nixos-container"`.

Move each `containerService` value to `backend."nixos-container".service`.

Move each `containerName` value to `backend."nixos-container".name`.

Add `backend.host = "localhost"` to services that currently rely on the implicit localhost default.

Update these consumer files:

- `machines/citadel/service-minecraft.nix`
- `machines/citadel/service-nixos-admin.nix`
- `machines/citadel/service-zellij-web.nix`
- `machines/nexus/service-ha-proxy.nix`
- `machines/nexus/service-nexus-admin.nix`
- `machines/nexus/service-syncthing.nix`
- `machines/nexus/service-brain-serve.nix`
- `machines/nexus/service-copyparty.nix`
- `machines/nexus/service-dump.nix`
- `machines/nexus/service-firefly-importer.nix`
- `machines/nexus/service-firefly.nix`
- `machines/nexus/service-gitea.nix`
- `machines/nexus/service-gitea-runner.nix`
- `machines/nexus/service-github-runner.nix`
- `machines/nexus/service-hedgedoc2.nix`
- `machines/nexus/service-jazzy-poisonous-plant-parlour.nix`
- `machines/nexus/service-lidarr.nix`
- `machines/nexus/service-llm-proxy.nix`
- `machines/nexus/service-music.nix`
- `machines/nexus/service-opengist.nix`
- `machines/nexus/service-overview.nix`
- `machines/nexus/service-prowlarr.nix`
- `machines/nexus/service-radarr.nix`
- `machines/nexus/service-redis.nix`
- `machines/nexus/service-scout.nix`
- `machines/nexus/service-scout-static.nix`
- `machines/nexus/service-sonarr.nix`
- `machines/nexus/service-torrent.nix`

Verify each path before editing. The current repository may not contain every path in this list on a future branch.

Keep these raw OCI files unchanged during the first backend implementation:

- `machines/nexus/service-jellyfin.nix`
- `machines/nexus/service-jaeger.nix`

Update all backend-shaped fixtures in `modules/services/surmhosting/tests.nix`. Do not retain compatibility fixtures or compatibility definitions.

After migration, run this supplemental source audit:

```sh
rg -n 'services\.surmhosting\.services\..*(\.host|\.container)|^\s*(host|container|containerName|containerService)\s*=' \
  machines modules --glob '*.nix'
```

Inspect every match because the broad expression also finds unrelated local fields. No match may be a legacy Surmhosting backend declaration. The Nexus and Citadel evaluations provide the authoritative check for removed option uses.

## 15. Full configuration verification

Run the focused evaluation tests before building host configurations.

Run a direct evaluation that inspects the effective OCI configuration:

```sh
nix eval --offline --no-write-lock-file --impure --json \
  --expr '
    let
      f = builtins.getFlake ("git+file://" + toString ./.);
      nexus = f.nixosConfigurations.nexus.config;
      managed = f.inputs.nixpkgs.lib.filterAttrs
        (name: _: f.inputs.nixpkgs.lib.hasPrefix "surmhosting-" name)
        nexus.virtualisation.oci-containers.containers;
    in {
      podmanEnabled = nexus.virtualisation.podman.enable or false;
      ociBackend = nexus.virtualisation.oci-containers.backend;
      managedContainers = builtins.mapAttrs (_: value: {
        inherit (value) serviceName networks ports labels;
      }) managed;
    }
  '
```

Nexus must keep Podman enabled because Jellyfin and Jaeger already use the raw OCI module. A managed Podman backend implies Podman enablement, but it is not the only possible cause. The output may contain no managed containers until a Nexus service selects `backend.podman`.

Build the Nexus system closure:

```sh
nix build --no-link --impure --expr \
  'let
     f = builtins.getFlake (toString ./.);
   in
     f.nixosConfigurations.nexus.config.system.build.toplevel'
```

Build the Citadel system closure:

```sh
nix build --no-link --impure --expr \
  'let
     f = builtins.getFlake (toString ./.);
   in
     f.nixosConfigurations.citadel.config.system.build.toplevel'
```

Run the repository checks that the flake exposes. Run `git diff --check` after every migration batch.

Do not deploy during this implementation phase. A later deployment requires explicit approval for the target host and flake revision.

## 16. Suggested implementation commits

Use separate commits so each change has a clear review boundary:

1. `Replace legacy Surmhosting backend options` with the resolver, NixOS adapter, consumer migration, and updated fixtures.
2. `Add rootful Podman backend` with its explicit option contract and focused tests.
3. `Add Podman network lifecycle` with per-start validation and focused tests.
4. `Add Podman Surmhosting runtime test`.

Pair each new contract test with the implementation that makes it pass. Each commit must pass its focused verification command before the next commit starts.

Create commits with `--no-gpg-sign`.

Do not commit directly to `main`. Use a feature branch and push each meaningful commit for review.

## 17. Acceptance criteria

The implementation is complete when all of these statements hold:

- A service can select `backend.host`.
- A service can select `backend."nixos-container"`.
- A service can select `backend.podman`.
- The module rejects missing or multiple selected backends.
- The module no longer defines the old backend options.
- Every repository consumer uses the explicit backend namespace.
- Podman enables automatically when a Podman backend exists.
- Podman runs rootfully.
- Each Podman service receives one private `/30` network.
- Each Podman service receives a stable fixed address.
- Traefik targets the fixed address independently of any published ports.
- Managed OCI containers force `traefik.enable=false` and receive no Docker-provider route.
- Explicitly configured published ports reach the OCI declaration unchanged.
- Network creation and verification run before every OCI service start.
- An absent network is created automatically.
- A mismatched network fails without automatic deletion.
- Podman egress works through NAT.
- Managed OCI logs appear in journald.
- Existing NixOS-container routing remains unchanged.
- Existing host backend routing remains unchanged.
- Existing authentication routes remain unchanged.
- Focused evaluation fixtures pass.
- The runtime VM test passes.
- Nexus and Citadel system closures build.
- Repository consumers use explicit backend declarations.
- Raw Jellyfin and Jaeger OCI declarations remain unchanged until their separate migrations receive access-policy decisions.

## 18. Follow-up work

Consider these items after the first implementation:

- Add internal DNS for stable service and host-gateway names. Replace literal `10.201.<service-index>.1` references where practical.
- Add a documented operator command for removing an obsolete managed network.
- Migrate Jellyfin after adding an internal-only logical-app mode.
- Migrate Jaeger after deciding its OTLP and HTTP exposure contract.
- Replace hash-derived slots with a persistent allocator if explicit collision overrides become burdensome.
- Add image digest validation for production services.
- Add resource limits and healthcheck policy to the public backend contract.
- Remove the legacy `docker.enable` name after the Traefik provider migration finishes.
