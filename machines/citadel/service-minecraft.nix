{ pkgs, lib, ... }:
let
  ports = import ./ports.nix;

  # Pin the in-container minecraft uid/gid so the persistent host bind-mount
  # directory has stable ownership across host rebuilds (otherwise the tmpfiles
  # rule below would fight the container's own chown).
  minecraftUid = 2000;

  # The minecraft-server module has no option for operators, so we seed
  # ops.json declaratively. The server rewrites ops.json at runtime (/op,
  # /deop), but this preStart copy reasserts SurmBob as a permanent op on every
  # (re)start. UUID resolved via the Mojang API for username "SurmBob".
  opsFile = pkgs.writeText "ops.json" (
    builtins.toJSON [
      {
        uuid = "39473849-d69a-4a6b-8f9b-18679572254a";
        name = "SurmBob";
        level = 4;
        bypassesPlayerLimit = false;
      }
    ]
  );
in
{
  networking.firewall.allowedTCPPorts = [ ports.minecraft ];

  # systemd-nspawn cannot create a bind-mount source, so the host directory
  # must exist (and be owned by the container's minecraft user) before the
  # container starts. Mirrors the tmpfiles pattern in service-scout.nix.
  systemd.tmpfiles.rules = [
    "d /var/lib/minecraft 0750 ${toString minecraftUid} ${toString minecraftUid} - -"
  ];

  # Minecraft is raw TCP, not HTTP, so it does NOT use surmhosting's Traefik
  # `expose` mechanism. Instead we NAT the port straight into the container,
  # mirroring the gitea SSH-port pattern on nexus (machines/nexus/service-gitea.nix).
  services.surmhosting.services.minecraft = {
    # surmhosting caps containers at 4G by default; bump it above the JVM heap.
    containerService.serviceConfig.MemoryMax = "8G";

    container = {
      # Function form so we build the (unfree) server package with the
      # container's pkgs, which sets allowUnfree below. The host pkgs has
      # allowUnfree = false.
      config =
        { pkgs, lib, ... }:
        let
          # nixpkgs only ships 1.21.x; Mojang's current release is 26.2
          # (calendar versioning). Build the official server jar with
          # upstream's own wrapper derivation. 26.2 requires Java 25 per
          # Mojang's version manifest (javaVersion.majorVersion = 25).
          minecraftServer = pkgs.callPackage (pkgs.path + "/pkgs/by-name/mi/minecraft-server/derivation.nix") {
            version = "26.2";
            url = "https://piston-data.mojang.com/v1/objects/823e2250d24b3ddac457a60c92a6a941943fcd6a/server.jar";
            sha1 = "823e2250d24b3ddac457a60c92a6a941943fcd6a";
            jre_headless = pkgs.jdk25_headless;
          };
        in
        {
          system.stateVersion = "25.05";
          nixpkgs.config.allowUnfree = true; # minecraft-server is unfree

          # Pin uid/gid to match the host bind-mount directory ownership.
          users.users.minecraft.uid = minecraftUid;
          users.groups.minecraft.gid = minecraftUid;

          services.minecraft-server = {
            enable = true;
            package = minecraftServer;
            eula = true;
            openFirewall = true; # opens the port inside the container
            dataDir = "/var/lib/minecraft";
            jvmOpts = "-Xmx6G -Xms6G";

            # `declarative` makes serverProperties + whitelist authoritative:
            # NixOS now owns server.properties and whitelist.json (rewritten on
            # every (re)start). Required for the whitelist option to apply.
            declarative = true;
            serverProperties = {
              server-port = ports.minecraft;
              white-list = true;
              enforce-whitelist = true;
            };

            # Allowlisted accounts (dashed Mojang UUIDs). Add colleagues as
            # `Username = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";`.
            whitelist = {
              SurmBob = "39473849-d69a-4a6b-8f9b-18679572254a";
              ExploB0b = "5acde26f-a399-4130-8525-584d23021d80";
            };
          };

          # Seed the operator list (see opsFile note above). Runs in the
          # service's WorkingDirectory (dataDir) as the minecraft user, so
          # ops.json ends up writable by the server.
          systemd.services.minecraft-server.preStart = lib.mkAfter ''
            install -m 0644 ${opsFile} ops.json
          '';
        };

      forwardPorts = [
        {
          containerPort = ports.minecraft;
          hostPort = ports.minecraft;
          protocol = "tcp";
        }
      ];

      # Containers are ephemeral (root wiped on restart); persist world data
      # on a host bind mount.
      bindMounts."/var/lib/minecraft" = {
        hostPath = "/var/lib/minecraft";
        isReadOnly = false;
      };
    };
  };
}
