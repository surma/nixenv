{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
with lib;
{
  options = {
    defaultConfigs.iamb = {
      enable = mkEnableOption "";
    };
  };
  config = mkIf (config.defaultConfigs.iamb.enable) {
    programs.iamb = {
      package = pkgs-unstable.iamb;
      settings = {
        profiles.user.user_id = "@surma:matrix.surma.technology";
        # iamb's `:open` aborts without a download dir, even for plain links.
        # It falls back to $XDG_DOWNLOAD_DIR, which is unset on our Linux machines.
        dirs.downloads = "${config.home.homeDirectory}/Downloads";
      };
    };
  };
}
