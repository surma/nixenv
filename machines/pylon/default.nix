{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./service-surm-auth.nix
    ./service-llm-proxy.nix
    ./service-syncthing-relay.nix
    ./service-traefik-tracing.nix
    ./service-gitea-ssh.nix
    ./service-music-proxy.nix
    ./service-ha-proxy.nix
    ./service-gitea-proxy.nix
    ./service-dump-proxy.nix
    ./service-brain-proxy.nix
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting

    # ../../apps/writing-prompt
  ];

  nix.settings.require-sigs = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "pylon";
  networking.networkmanager.enable = true;

  users.users.surma.linger = true;
  users.groups.podman.members = [ "surma" ];

  users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
    surma
    surmbook
    shopisurm
    citadel
  ];

  networking.interfaces.enp1s0.useDHCP = true;
  networking.interfaces.enp1s0.ipv6.addresses = [
    {
      address = "2a01:4f8:c17:731::1";
      prefixLength = 64;
    }
  ];

  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };

  secrets.identity = "/home/surma/.ssh/id_machine";

  home-manager.users.surma = import ./home.nix;

  services.surmhosting.enable = true;
  services.surmhosting.externalInterface = "enp1s0";
  services.surmhosting.hostname = "surmedge";
  services.surmhosting.dashboard.enable = false;
  services.surmhosting.tls.enable = true;
  services.surmhosting.tls.email = "surma@surma.dev";
  services.surmhosting.docker.enable = true;

  virtualisation.oci-containers.backend = "podman";

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.tailscale.enable = true;
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
