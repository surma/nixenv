{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  isEnabled = config.defaultConfigs.web-search-cli.enable;
  cfg = config.defaultConfigs.web-search-cli.llmProxy;
  defaultTokenPath = "${config.home.homeDirectory}/.local/state/opencode/api-key";

  wrappedPackage = import ./package.nix {
    inherit pkgs lib inputs;
    authTokenFile = cfg.authTokenFile;
    perplexityApiBase = cfg.perplexityApiBase;
    browserExecutable =
      if pkgs.stdenv.isDarwin then lib.getExe pkgs.google-chrome else lib.getExe pkgs.chromium;
  };
in
with lib;
{
  options = {
    defaultConfigs.web-search-cli = {
      enable = mkEnableOption "";

      llmProxy = {
        manageSecret = mkOption {
          type = types.bool;
          default = true;
          description = "Whether this module should also manage the web-search auth token secret file.";
        };

        authTokenFile = mkOption {
          type = types.nullOr types.path;
          default = lib.attrByPath [ "secrets" "items" "llm-proxy-client-key" "target" ] null config;
          description = "Path to file containing the auth token for web-search-cli";
        };

        perplexityApiBase = mkOption {
          type = types.str;
          default = "https://vendors.llm.surma.technology/perplexity";
          description = "Base URL for the Perplexity vendor route";
        };
      };
    };
  };

  config = mkMerge [
    (mkIf isEnabled {
      programs.web-search-cli.enable = true;
      programs.web-search-cli.package = mkDefault wrappedPackage;
    })

    (mkIf (isEnabled && cfg.manageSecret) {
      secrets.items.llm-proxy-client-key.target = mkDefault defaultTokenPath;
    })
  ];
}
