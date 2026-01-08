{ config, pkgs, ... }:
let
  inherit (pkgs) writeShellApplication;

  vinylForwarding = writeShellApplication {
    name = "vinyl-forwarding";
    runtimeInputs = with pkgs; [
      nushell
      ecasound
      alsa-utils
    ];
    text = ''
      nu ${../apps/surmturntable/vinyl-forward.nu}
    '';
  };

  respotService = writeShellApplication {
    name = "respot";
    runtimeInputs = with pkgs; [
      librespot
    ];
    text = ''
      librespot -b 320 -n SurmTurntable -R 100
    '';
  };

  shairportService = writeShellApplication {
    name = "shairport";
    runtimeInputs = with pkgs; [
      shairport-sync
    ];
    text = ''
      shairport-sync -a SurmTurntable
    '';
  };
in
{
  imports = [

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/linux.nix
  ];
  home.packages = (with pkgs; [ ]);

  systemd.user.services.vinyl-forwarding = {
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = ''
        ${vinylForwarding}/bin/vinyl-forwarding
      '';
      Environment = [
        "TERM=xterm"
      ];
    };
  };

  systemd.user.services.respot = {
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = ''
        ${respotService}/bin/respot
      '';
    };
  };

  systemd.user.services.shairport = {
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = ''
        ${shairportService}/bin/shairport
      '';
    };
  };

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmturntable";
}
