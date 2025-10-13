{ config, pkgs, ... }:
let
  inherit (pkgs) writeShellApplication;

  vinylForwarding = writeShellApplication {
    name = "vinyl-forwarding";
    runtimeInputs = with pkgs; [nushell ecasound alsa-utils];
    text = ''
        nu ${../apps/surmturntable/vinyl-forward.nu}
    '';
  };
in
{
  imports = [

    ../home-manager/base.nix
    ../home-manager/dev.nix
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
        "HOME=%h"
      ];
      # User = "surma";
      # Group="audio";
      # LimitMEMLOCK = "infinity";
      # LimitRTPRIO= 95;
      # LimitNICE=-10;
      # IOSchedulingClass="real-time";
      # IOSchedulingPriority=0;
    };
  };

  
  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmturntable";
}
