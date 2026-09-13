# Surmhosting

Surmhosting is an opinionated NixOS hosting module for nixenv. It configures Traefik, generated NixOS containers, public firewall ports, optional Podman discovery, and the bundled `surm-auth` service.

Stage 1 keeps the implementation in nixenv. The flake exports `nixosModules.surmhosting`, and the stable local import path remains `modules/services/surmhosting`. This document does not define standalone-repository support.

## Basic use

A host imports the module and supplies its required identity and network values:

```nix
{
  imports = [ ../../modules/services/surmhosting ];

  services.surmhosting = {
    enable = true;
    hostname = "nexus";
    externalInterface = "enp1s0";
  };
}
```

Surmhosting enables Traefik when `services.surmhosting.enable` is true. It generates HTTP routes from the declared services and apps.

## Ownership

Surmhosting owns:

- Traefik, its entrypoints, generated routers, services, middleware, and certificate resolvers.
- Default network values for supplied NixOS containers.
- The Surmhosting NAT ranges through native `networking.nat` options.
- Public firewall ports 80 and 443.
- The optional Podman Docker-compatible socket and Traefik Docker provider.
- The bundled `surm-auth` container and its generated policy configuration.
- Read-only credential mounts and the read-write auth state mount.

The consumer owns:

- Supplied NixOS container configuration, packages, services, users, devices, and bind mounts.
- Host backends and their service ports.
- Explicit container addresses and native NAT overrides.
- Credential files, the auth state directory, and their permissions.
- Service-to-service firewall rules and access to the internal Traefik port.
- OCI container declarations and their Traefik labels.

Surmhosting does not create credential or state paths. The consumer must create them before the relevant container starts.

## Supplied NixOS containers

A service can supply a complete NixOS container configuration. Surmhosting adds defaults around that configuration:

```nix
services.surmhosting.services.hedgedoc = {
  containerName = "hedgedoc";
  container = {
    localAddress = "10.50.0.2/24";
    hostAddress = "10.50.0.1/24";
    config = {
      system.stateVersion = "25.05";
      services.hedgedoc.enable = true;
    };
  };

  expose.ports = [
    {
      port = 3000;
      hostname = "hedgedoc";
    }
  ];
};
```

The container keeps the complete address, including `/24`. Traefik uses `10.50.0.2` in generated backend URLs. Every exposed workload container must have a usable IPv4 local address with an optional CIDR suffix.

A host can override normal NixOS options inside `container.config`:

```nix
services.surmhosting.services.hedgedoc.container.config.networking.nameservers = [
  "1.1.1.1"
];
```

Surmhosting applies workload nameservers with `lib.mkDefault`. It does not provide a per-service network option.

## Host backends

A service can forward to a host address instead of creating a container:

```nix
services.surmhosting.services.admin = {
  host = "127.0.0.1";
  expose.port = 8092;
};
```

`expose.port` creates one port entry with the service name as its hostname. Use `expose.ports` for explicit port names and rules.

## Generated defaults and overrides

Surmhosting generates these workload defaults with normal NixOS option priority:

- `containerName` defaults to `lc-<first-ten-service-characters>`.
- `localAddress` defaults to `10.201.<lexical-index>.2`.
- `hostAddress` defaults to `10.201.<lexical-index>.1`.
- `privateNetwork`, `ephemeral`, and `autoStart` default to true.
- Workload nameservers default to `[ "8.8.8.8" ]`.
- `containeruser.name` defaults to `containeruser`.
- `containeruser.uid` defaults to null.
- `containerLimits.memoryMax` defaults to `4G`.
- `containerLimits.memorySwapMax` defaults to `0`.

Set the corresponding value in the supplied container configuration to override a generated workload default. Traefik reads the final evaluated local address outside the nested container configuration.

The native NAT default is:

```nix
networking.nat.internalIPs = [
  "10.201.0.0/16"
  "10.202.0.0/16"
];
```

The module sets this value with `lib.mkDefault`. Override `networking.nat.internalIPs` directly when custom container networks need different ranges.

The auth network defaults are `10.202.0.1` for `hostAddress` and `10.202.0.2` for `localAddress`. The auth container keeps complete configured values. Auth URLs remove an optional CIDR suffix from the final local address. The two auth addresses must differ.

## Bundled authentication

Enable the bundled v2 auth service with:

```nix
services.surmhosting = {
  tls.enable = true;

  auth = {
    enable = true;
    domain = "auth.example.com";
    cookieDomain = ".example.com";
    stateHostPath = "/var/lib/surm-auth-state";
    github.clientIdFile = "/var/lib/surm-auth-credentials/github-client-id";
    github.clientSecretFile = "/var/lib/surm-auth-credentials/github-client-secret";
    cookieSecretFile = "/var/lib/surm-auth-credentials/cookie-secret";
  };
};
```

The auth container receives these fixed paths:

- State: `/var/lib/private`.
- GitHub client ID: `/var/lib/secrets/github-client-id`.
- GitHub client secret: `/var/lib/secrets/github-client-secret`.
- Cookie secret: `/var/lib/secrets/cookie-secret`.

The public credential and state options use external paths. Use quoted absolute paths outside the Nix store. The consumer owns their creation, contents, permissions, and persistence. The module does not create, decrypt, chmod, or chown them.

The auth service requires TLS. The default auth unit has no secret-manager dependency. Use `auth.unitDependencies` when a consumer needs explicit unit ordering.

## Firewall ownership

With `firewall.enable = true`, Surmhosting sets `networking.firewall.enable = lib.mkDefault true`. It opens port 80 when a public HTTP entrypoint exists. It opens port 443 when TLS is enabled.

Surmhosting adds no trusted interface and no rule for `internalPort`. The consumer owns access to the internal entrypoint and all service-to-service access. For example:

```nix
networking.firewall.extraInputRules = ''
  ip saddr { 10.0.0.0/8, 100.64.0.0/10 }
    tcp dport 8081 accept comment "surmhosting internal HTTP"
'';
```

Set `firewall.enable = false` when the host owns all public firewall management. An explicit host value such as `networking.firewall.enable = false` wins over Surmhosting's default.

## Optional OCI discovery

Set `docker.enable = true` to enable Podman, Docker compatibility, the Podman Docker socket, the Traefik `podman` group, and the Traefik Docker provider:

```nix
services.surmhosting.docker.enable = true;

virtualisation.oci-containers.backend = "podman";
virtualisation.oci-containers.containers.example = {
  image = "example/image:latest";
  ports = [ "8080:8080" ];
  labels = {
    "traefik.enable" = "true";
    "traefik.http.routers.example.rule" = "Host(`example.example.com`)";
    "traefik.http.services.example.loadbalancer.server.port" = "8080";
  };
};
```

OCI declarations and labels remain consumer-owned. Surmhosting only enables Traefik discovery for them.

## Public options

All options use the `services.surmhosting` namespace unless stated otherwise.

### Host and container defaults

- `enable`: Enables Surmhosting. The default is `false`.
- `externalInterface`: Required host interface for NAT.
- `hostname`: Required hostname suffix for generated Traefik rules.
- `network.nameservers`: Nameservers for workload and auth containers. The default is `[ "8.8.8.8" ]`.
- `containeruser.name`: Default workload user name. The default is `containeruser`.
- `containeruser.uid`: Optional workload user UID. The default is `null`.
- `containerLimits.memoryMax`: Default `MemoryMax` for generated container units. The default is `4G`.
- `containerLimits.memorySwapMax`: Default `MemorySwapMax` for generated container units. The default is `0`.

### TLS and Traefik

- `tls.enable`: Enables HTTPS and port 443. The default is `false`.
- `tls.unitDependencies.wants`: Extra `Wants=` dependencies for `traefik.service`. The default is `[ ]`.
- `tls.unitDependencies.requires`: Extra `Requires=` dependencies for `traefik.service`. The default is `[ ]`.
- `tls.unitDependencies.after`: Extra `After=` dependencies for `traefik.service`. The default is `[ ]`.
- `tls.challenge`: ACME challenge, either `http-01`, `dns-01`, or `null`. The default is `null`.
- `tls.dnsProvider`: DNS-01 provider. The default is `cloudflare`.
- `tls.dnsEnvironmentFile`: Optional environment file for the DNS provider. DNS-01 requires this value.
- `tls.certDomains`: Extra certificates. Each entry has required `main` and optional `sans`, which defaults to `[ ]`.
- `tls.email`: Optional ACME email. The default is `null`.
- `tls.acmeFile`: ACME storage path. The default is `/var/lib/traefik/acme.json`.
- `appsNamespace`: Public app domain namespace. The default is `null`.
- `internalPort`: Internal Traefik entrypoint port. The default is `8081`.
- `dashboard.enable`: Enables the Traefik dashboard router. The default is `false`.
- `dashboard.rule`: Dashboard router rule. The default uses `HostRegexp` with pattern `^dashboard\\.surmcluster`.
- `docker.enable`: Enables Podman-backed Docker discovery. The default is `false`.
- `firewall.enable`: Enables Surmhosting public firewall management. The default is `true`.

### Authentication

- `auth.enable`: Enables the bundled v2 auth container. The default is `false`.
- `auth.domain`: Canonical auth domain. The default is `null` and auth requires a value.
- `auth.aliases`: Additional auth domains. The default is `[ ]`.
- `auth.network.hostAddress`: Host-side auth address. The default is `10.202.0.1`.
- `auth.network.localAddress`: Container-side auth address. The default is `10.202.0.2`.
- `auth.unitDependencies.wants`: Extra `Wants=` dependencies for `container@surm-auth`. The default is `[ ]`.
- `auth.unitDependencies.requires`: Extra `Requires=` dependencies for `container@surm-auth`. The default is `[ ]`.
- `auth.unitDependencies.after`: Extra `After=` dependencies for `container@surm-auth`. The default is `[ ]`.
- `auth.stateHostPath`: External host path for auth state. The default is `null` and auth requires a value.
- `auth.github.clientIdFile`: External GitHub client ID path. The default is `null` and auth requires a value.
- `auth.github.clientSecretFile`: External GitHub client secret path. The default is `null` and auth requires a value.
- `auth.cookieSecretFile`: External cookie secret path. The default is `null` and auth requires a value.
- `auth.cookieDomain`: Session cookie domain. The default is `.${hostname}`.
- `auth.sessionDuration`: Session duration. The default is `168h`.
- `auth.policyFile`: Auth policy path inside the container. The default is `/var/lib/surm-auth/policy.json`.
- `auth.auditFile`: Auth audit path inside the container. The default is `/var/lib/surm-auth/audit.log`.
- `auth.bootstrapAdmins`: Nix-owned admin identities. Each entry has a required `id` and `provider`, which defaults to `github`.

### Service declarations

Each `services.<name>` entry supports these options:

- `host`: Host backend address. The default is `null`.
- `container`: Optional pass-through NixOS container attributes. The default is `null`.
- `containerName`: Container name override. The default is `null`.
- `containerService.wants`: Extra `Wants=` dependencies for the generated container unit. The default is `[ ]`.
- `containerService.requires`: Extra top-level `Requires=` dependencies. The default is `[ ]`.
- `containerService.after`: Extra `After=` dependencies. The default is `[ ]`.
- `containerService.serviceConfig`: Extra service settings for the generated container unit. The default is `{ }`.
- `expose.enable`: Enables Traefik exposure. The default follows whether `port`, `ports`, or `apps` is non-empty.
- `expose.rule`: Rule for single-port mode. The default is `null`.
- `expose.port`: Single backend port. The default is `null`.
- `expose.ports`: Explicit legacy port declarations. The default is `[ ]`.
- `expose.apps`: Logical app declarations. The default is `{ }`.
- `expose.allowedGitHubUsers`: Legacy seed adapter for one allowlist app. The default is `[ ]`.
- `expose.useTargetHost`: Rewrites the forwarded `Host` header for host backends. The default is `false`.

Each `expose.ports` entry supports:

- `port`: Required backend port.
- `hostname`: Required hostname prefix.
- `rule`: Optional custom Traefik rule. The default is `null`.

Each `expose.apps.<key>` entry supports:

- `access.mode`: Required `public` or `allowlist` mode.
- `access.seedUsers`: Initial usernames for allowlist mode. The default is `[ ]`.
- `internal.enable`: Generates an internal router. The default is `true`.
- `internal.access`: Internal policy, currently `trusted-network`. The default is `null`.
- `public.aliases`: Additional public domains. The default is `[ ]`.
- `ports`: App backend ports. The default is `[ ]`.

Each `expose.apps.<key>.ports` entry supports:

- `port`: Required backend port.
- `hostname`: Required hostname prefix.
- `internalRule`: Optional internal router rule. The default is `null`.
- `publicPathPrefixes`: Optional public path prefixes. The default is `[ ]`.
- `publicPriority`: Public router priority. The default is `1`.

## Stage 1 checks

Run the focused module check, auth check, and existing auth package build on x86 Linux:

```text
nix eval .#nixosModules.surmhosting
nix build --no-link .#checks.x86_64-linux.surmhosting-module
nix build --no-link .#checks.x86_64-linux.surm-auth-e2e
nix build --no-link .#packages.x86_64-linux.surm-auth
```

The module check evaluates synthetic NixOS fixtures. The auth check runs the packaged binary through its mocked OAuth flow. These checks do not deploy a host.
