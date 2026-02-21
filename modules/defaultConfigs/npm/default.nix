{ config, lib, ... }:
with lib;
{
  options.defaultConfigs.npm.enable = mkEnableOption "default npm configuration";

  config = mkIf config.defaultConfigs.npm.enable {
    home.file.".npmrc" = {
      text = ''
        init-author-name = "Surma"
        init-author-email = "surma@surma.dev"
        init-license = "MIT"
        init-version = "0.0.1"
        init-type = "module"
        prefix=${config.home.homeDirectory}/.npm-global
      '';
      mutable = true;
    };
  };
}
