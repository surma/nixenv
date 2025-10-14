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
      zsh
    ];
    text = ''
      librespot -b 320 -n SurmTurntable -R 100
    '';
  };
in
{
  imports = [

    ../home-manager/base.nix
    ../home-manager/dev.nix
    ../home-manager/workstation.nix
    ../home-manager/linux.nix
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

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmturntable";
}
