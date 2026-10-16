# Supply Depot: food and weight tracking (https://gitea.surma.technology/surma/supply-depot).
#
# A nexus.apps app (modules/services/nexus-apps): nixenv only allocates the
# container; nixos-admin builds the app's own flake into the container's
# app profile and restarts `app.service`. Deploy gate: every push to `main`
# deploys its head (deployOn = "push", the default; merges to main are gated
# by the repo's Gitea CI), triggered by the repo's Gitea webhook
# (service-gitea.nix). nixenv's flake.lock does not pin the app; the apps
# page of nixos-admin shows what runs and rolls back.
#
# The app uses the global PostgreSQL (role and database `supply-depot`, see
# service-postgresql.nix). It keeps no other state on disk.
{ ... }:
let
  ips = import ../../ips.nix;
  passwordDir = "/var/lib/postgres-supply-depot";
in
{
  # Note for agents: container addresses may change when a service is added. That is fine.
  # Surmhosting routes everything by name, so do not pick service keys or container names
  # to keep addresses stable.
  nexus.apps.supply-depot = {
    flake = "git+ssh://containeruser@gitea.surma.technology:2222/surma/supply-depot.git";

    requires = [ "postgres-supply-depot-setup.service" ];
    after = [ "postgres-supply-depot-setup.service" ];

    # The password folder (root:postgres 0750, password 0440) is bound read-only
    # to /run/app-secrets/db. app.service runs as containeruser, so systemd
    # (root in the container) hands it the password as a credential.
    secrets.db = passwordDir;

    env = {
      HOST = "0.0.0.0";
      PORT = "8080";
      NODE_ENV = "production";
      # `_gateway` resolves to this container's current host-side address.
      DATABASE_URL = "postgres://supply-depot@_gateway:5432/supply-depot";
      DATABASE_PASSWORD_FILE = "%d/db-password";
    };

    containerConfig = {
      systemd.services.app = {
        serviceConfig.LoadCredential = [ "db-password:/run/app-secrets/db/password" ];
        # Start only after nscd is up, so `_gateway` resolves (see the
        # supply-depot NixOS module for the reason).
        wants = [ "nss-lookup.target" ];
        after = [ "nss-lookup.target" ];
      };
    };

    healthUrl = "http://supply-depot.nexus.hosts.${ips.hosts.nexus.ip}.nip.io:8081/";

    expose.apps.supply-depot = {
      access.mode = "allowlist";
      access.seedUsers = [ "surma" ];
      # Scout reaches the API from the trusted network, without the OAuth login.
      internal.access = "trusted-network";
      public.aliases = [ "supply-depot.surma.technology" ];
      ports = [
        {
          port = 8080;
          hostname = "supply-depot";
        }
      ];
    };
  };
}
