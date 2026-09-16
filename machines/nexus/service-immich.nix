{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  package = inputs.nixpkgs-immich.legacyPackages.${system}.immich;
  baseUrl = "https://immich.apps.surma.technology";
  stateDirectory = "/dump/state/immich";
in
{
  systemd.services.immich-state = {
    description = "Create Immich state directories";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 ${stateDirectory}
      ${pkgs.coreutils}/bin/install -d -m 0700 \
        ${stateDirectory}/media \
        ${stateDirectory}/ml-cache \
        ${stateDirectory}/redis
      ${pkgs.coreutils}/bin/install -d -m 0700 -o postgres -g postgres \
        ${stateDirectory}/postgresql
    '';
  };

  # Keep this service last in Surmhosting's lexical address allocation.
  # This name prevents changes to existing container and Podman addresses.
  services.surmhosting.services."zz-immich" = {
    backend."nixos-container" = {
      name = "lc-immich";

      service = {
        requires = [ "immich-state.service" ];
        after = [ "immich-state.service" ];
        serviceConfig.MemoryMax = "8G";
      };

      bindMounts = {
        media = {
          mountPoint = "/var/lib/immich";
          hostPath = "${stateDirectory}/media";
          isReadOnly = false;
        };
        postgresql = {
          mountPoint = "/var/lib/postgresql";
          hostPath = "${stateDirectory}/postgresql";
          isReadOnly = false;
        };
        ml-cache = {
          mountPoint = "/var/cache/immich";
          hostPath = "${stateDirectory}/ml-cache";
          isReadOnly = false;
        };
        redis = {
          mountPoint = "/var/lib/redis-immich";
          hostPath = "${stateDirectory}/redis";
          isReadOnly = false;
        };
      };

      config = {
        system.stateVersion = "25.05";

        services.immich = {
          enable = true;
          inherit package;
          host = "";
          settings.server.externalDomain = baseUrl;
        };
      };
    };

    expose.apps.immich = {
      access.mode = "public";
      internal.access = "trusted-network";
      ports = [
        {
          port = 2283;
          hostname = "immich";
        }
      ];
    };
  };

  services.traefik.staticConfigOptions.entryPoints = {
    websecure.transport.respondingTimeouts.readTimeout = "10m";
    internal.transport.respondingTimeouts.readTimeout = "10m";
  };
}
