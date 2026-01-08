{
  config,
  pkgs,
  lib,
  ...
}:
let
  # As of now, need to downgrade v4l2loopback because v0.14 is incompatible with OBS' virtual cam.
  # OBS Version: 31.0.3, Latest attempt: 2025-07-03
  v4l2loopback = config.boot.kernelPackages.v4l2loopback.overrideAttrs (oldAttrs: rec {
    version = "0.13.2";
    src = pkgs.fetchFromGitHub {
      owner = "umlaeute";
      repo = "v4l2loopback";
      rev = "v${version}";
      sha256 = "sha256-rcwgOXnhRPTmNKUppupfe/2qNUBDUqVb3TeDbrP5pnU=";
    };
  });
in
with lib;
{
  options = {
    programs.obs.virtualCameraFix = mkEnableOption "";
  };

  config = mkIf (config.programs.obs.virtualCameraFix) {

    boot.kernelModules = [
      "v4l2loopback"
    ];
    boot.extraModulePackages = [
      v4l2loopback
    ];

    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
  };
}
