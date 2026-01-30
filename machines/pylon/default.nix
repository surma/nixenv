{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
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
    surmrock
    surmbook
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
    interface = "enp1s0"; # Replace eth0 with your actual interface name
  };

  secrets.identity = "/home/surma/.ssh/id_machine";

  home-manager.users.surma =
  home-manager.users.surma = import ./home.nix;
}
