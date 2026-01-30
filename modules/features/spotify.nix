{ lib, config, pkgs, systemManager, inputs, ... }:
let
  mkElectronWrapper = pkgs.callPackage (import ../../lib/make-electron-wrapper.nix) { };
in
with lib;
{
  options = {
    programs.spotify = {
      enable = mkEnableOption "Spotify";
      package = mkPackageOption pkgs "spotify" { };
      platform = mkOption {
        type = with types; enum [ "wayland" "x11" "auto" ];
        default = "auto";
        description = "Which platform to use for Spotify (wayland/x11/auto)";
      };
    };
  };

  config = mkIf (config.programs.spotify.enable && systemManager == "home-manager") {
    home.packages = [
      (mkElectronWrapper {
        name = "spotify";
        desktopName = "Spotify";
        binName = "spotify";
        inherit (config.programs.spotify) platform package;
      })
    ];
  };
}
