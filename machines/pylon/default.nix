{
  config,
  pkgs,
  inputs,
  ...
}:
let
  ports = import ./ports.nix;
  inherit (import ./constants.nix) nexusTsV4 citadelTsV4 pylonPublicV4;
in
{
  imports = [
    ./hardware.nix
    ./service-syncthing-relay.nix
    ./service-nixos-admin.nix
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix

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
    (builtins.readFile ../../assets/ssh-keys/id_deploy.pub)
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

  # Pylon is now a packet forwarder only: no TLS termination, no HTTP
  # parsing, no surm-auth, no LLM receivers (auth-rework sections 2 and
  # 8.3). services.traefik stays disabled; all HTTP authority moved to
  # Nexus. The old proxy service files remain in this directory (not
  # imported) as rollback artifacts.
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

  # Forward the public web ports, Gitea SSH, and Minecraft to their
  # backend hosts over Tailscale. No HTTP parsing happens here; a public
  # Host header cannot select an internal router (auth-rework section
  # 8.1). Uses the pinned NAT option names: sourcePort, destination,
  # proto, loopbackIPs.
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp1s0";
  # Deliberately no internalIPs/internalInterfaces: no broad masquerade.
  # Return-path SNAT is narrowly scoped to DNAT'd traffic below.
  networking.nat.forwardPorts = [
    {
      sourcePort = 80;
      destination = "${nexusTsV4}:80";
      proto = "tcp";
      loopbackIPs = [ pylonPublicV4 ];
    }
    {
      sourcePort = 80;
      destination = "${nexusTsV4}:80";
      proto = "udp";
      loopbackIPs = [ pylonPublicV4 ];
    }
    {
      sourcePort = 443;
      destination = "${nexusTsV4}:443";
      proto = "tcp";
      loopbackIPs = [ pylonPublicV4 ];
    }
    {
      sourcePort = 443;
      destination = "${nexusTsV4}:443";
      proto = "udp";
      loopbackIPs = [ pylonPublicV4 ];
    }
    {
      sourcePort = ports.giteaSsh;
      destination = "${nexusTsV4}:${toString ports.giteaSsh}";
      proto = "tcp";
      loopbackIPs = [ pylonPublicV4 ];
    }
    {
      sourcePort = ports.minecraft;
      destination = "${citadelTsV4}:${toString ports.minecraft}";
      proto = "tcp";
      loopbackIPs = [ pylonPublicV4 ];
    }
  ];

  # Narrow source NAT for the forwarded destinations: replies to
  # externally originated connections must return through Pylon, since
  # the backend hosts would otherwise answer from their own addresses.
  # Scoped to `ct status dnat` traffic towards the two backend hosts —
  # no broad masquerade of unrelated tailnet traffic (auth-rework
  # section 8.1). Nexus ships no UDP web listener; UDP 80/443 forwarding
  # is transport provision only (section 8.2).
  networking.nftables.tables.surmedge-forward = {
    family = "ip";
    content = ''
      chain post {
        type nat hook postrouting priority srcnat; policy accept;
        ct status dnat oifname "tailscale0" ip daddr ${nexusTsV4} tcp dport { 80, 443, ${toString ports.giteaSsh} } masquerade
        ct status dnat oifname "tailscale0" ip daddr ${nexusTsV4} udp dport { 80, 443 } masquerade
        ct status dnat oifname "tailscale0" ip daddr ${citadelTsV4} tcp dport ${toString ports.minecraft} masquerade
      }
    '';
  };

  system.stateVersion = "25.05";
}
