{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
in
{
  imports = [
    ./unfree-apps.nix
  ];

  imports = [
    ../../modules/defaultConfigs/aerospace
    ../../modules/defaultConfigs/karabiner
  ];

  config = {
    defaultConfigs.aerospace.enable = true;
    defaultConfigs.karabiner.enable = true;

    home.sessionVariables = {
      # LIBRARY_PATH = ''${lib.makeLibraryPath [pkgs.iconv]}''${LIBRARY_PATH:+:$LIBRARY_PATH}'';
      CONFIG_MANAGER = "darwin-rebuild";
    };

    # Use 1password to unlock SSH key
    programs.ssh.matchBlocks."*".extraOptions = {
      "IdentityAgent" =
        ''"${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
    };

    programs.zsh = {
      initContent = ''
        export PNPM_HOME="/Users/surma/Library/pnpm"
        case ":$PATH:" in
          *":$PNPM_HOME:"*) ;;
          *) export PATH="$PNPM_HOME:$PATH" ;;
        esac
      '';
      # export PATH=$PATH:/run/current-system/sw/bin
    };
  };
}
