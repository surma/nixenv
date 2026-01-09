{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # ../../apps/traefik.nix
  ];

  boot.isContainer = true;

  networking.networkmanager.enable = false;
  networking.hostName = "testcontainer";
  # networking.dhcpcd.enable = false;

  environment.systemPackages = with pkgs; [
    helix
    nushell
  ];
  services.surmhosting.enable = true;
  services.surmhosting.hostname = "testcontainer";
  services.surmhosting.serverExpose = {
    test = {
      target = 8000;
    };
  };
  services.surmhosting.externalInterface = "eth0";

  systemd.services.writing-prompt = {
    enable = true;
    script = "${pkgs.simple-http-server}/bin/simple-http-server -p 8000 /";
    wantedBy = [ "default.target" ];
  };

  networking.firewall.enable = false;

  system.stateVersion = "25.05";
}
