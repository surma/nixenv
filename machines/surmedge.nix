{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../home-manager/unfree-apps.nix
    ./surmedge-hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../nixos/base.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "surmedge";
  networking.networkmanager.enable = true;

  programs.zsh.enable = true;

  users.users.surma.linger = true;
  users.groups.podman.members = [ "surma" ];

  users.users.root.openssh.authorizedKeys.keys = [ (../ssh-keys/id_ed25519.pub |> lib.readFile) ];
  home-manager.users.surma =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../home-manager/claude-code

        ../home-manager/base.nix
        ../home-manager/dev.nix
        ../home-manager/nixdev.nix
        ../home-manager/linux.nix
        ../home-manager/workstation.nix
        # ../home-manager/cloud.nix

        ../home-manager/unfree-apps.nix
      ];

      config = {
        allowedUnfreeApps = [
          "claude-code"
        ];

        home.packages = (
          with pkgs;
          [
            nftables
          ]
        );

        home.stateVersion = "25.05";

        home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmedge";

        programs.claude-code.enable = true;
        defaultConfigs.claude-code.enable = true;
      };
    };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  virtualisation.oci-containers.containers.test = {
    image = "docker.io/lipanski/docker-static-website:latest";
    volumes = [
      "/home/surma/src:/home/static"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.test.loadbalancer.server.port" = "3000";
      "traefik.http.routers.test.rule" = "HostRegexp(`^test\\.surmcluster`)";
    };
  };
  virtualisation.oci-containers.containers.test2 = {
    image = "docker-test:latest";
    imageFile = pkgs.dockerTools.buildImage {
      name = "docker-test";
      tag = "latest";
      copyToRoot = pkgs.buildEnv {
        name = "root";
        paths = [ (pkgs.callPackage (import ../testserver/default.nix) { }) ];
      };
      config = {
        Cmd = [ "req-dump-server" ];
      };
    };
    labels = {
      "traefik.enable" = "true";
      "traefik.http.services.test2.loadbalancer.server.port" = "8000";
      "traefik.http.routers.test2.rule" = "HostRegexp(`^test2\\.surmcluster`)";
    };
  };

  services.traefik = {
    enable = true;
    group = "podman";
    staticConfigOptions = {
      api = { };
      providers.docker = { };
      entryPoints = {
        web.address = ":80";
        websecure.address = ":443";
      };
    };
    dynamicConfigOptions = {
      http.routers.api = {
        service = "api@internal";
        # entryPoints = ["web" "websecure" ];
        # rule = "HostRegexp(`.*`)";
        rule = "HostRegexp(`^dashboard\\.surmcluster`)";
      };
    };
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];
  networking.nftables.enable = true;
  services.openssh.enable = true;

  system.stateVersion = "25.05";

}
