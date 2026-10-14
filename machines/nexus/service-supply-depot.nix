# Supply Depot: food and weight tracking (https://gitea.surma.technology/surma/supply-depot).
# The app runs in a container and uses the global PostgreSQL (role and database
# `supply-depot`, see service-postgresql.nix).
{ inputs, ... }:
{
  # Note for agents: container addresses may change when a service is added. That is fine.
  # Surmhosting routes everything by name, so do not pick service keys or container names
  # to keep addresses stable.
  services.surmhosting.services.supply-depot = {
    backend."nixos-container" = {
      service = {
        requires = [ "postgres-supply-depot-setup.service" ];
        after = [ "postgres-supply-depot-setup.service" ];
      };

      bindMounts.db-password = {
        mountPoint = "/var/lib/credentials/supply-depot";
        hostPath = "/var/lib/postgres-supply-depot";
        isReadOnly = true;
      };

      config = {
        imports = [ inputs.supply-depot.nixosModules.default ];
        system.stateVersion = "26.05";

        services.supply-depot = {
          enable = true;
          host = "0.0.0.0";
          port = 8080;
          database = {
            createLocally = false;
            # `_gateway` resolves to this container's current host-side address.
            host = "_gateway";
            passwordFile = "/var/lib/credentials/supply-depot/password";
          };
        };
      };
    };

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
