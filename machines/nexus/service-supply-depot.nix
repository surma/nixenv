# Supply Depot: food and weight tracking (https://gitea.surma.technology/surma/supply-depot).
# The app and its own PostgreSQL run in one container. The database lives on /dump.
{ inputs, pkgs, ... }:
let
  stateDirectory = "/dump/state/supply-depot";
in
{
  systemd.services.supply-depot-state = {
    description = "Create Supply Depot state directories";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 ${stateDirectory}
      ${pkgs.coreutils}/bin/install -d -m 0700 -o postgres -g postgres ${stateDirectory}/postgresql
    '';
  };

  # The key sorts after every existing key, so Surmhosting's lexical address allocation
  # does not move other containers (see service-immich.nix).
  services.surmhosting.services."zzz-supply-depot" = {
    backend."nixos-container" = {
      name = "lc-supdep";

      service = {
        requires = [ "supply-depot-state.service" ];
        after = [ "supply-depot-state.service" ];
      };

      bindMounts.postgresql = {
        mountPoint = "/var/lib/postgresql";
        hostPath = "${stateDirectory}/postgresql";
        isReadOnly = false;
      };

      config = {
        imports = [ inputs.supply-depot.nixosModules.default ];
        system.stateVersion = "26.05";

        services.postgresql.package = pkgs.postgresql_17;
        services.supply-depot = {
          enable = true;
          host = "0.0.0.0";
          port = 8080;
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
