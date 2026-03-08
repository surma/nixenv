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

  tokenExportCommand =
    if cfg.authTokenFile == null then
      null
    else
      "if [ -f \"${cfg.authTokenFile}\" ]; then export WEB_SEARCH_AUTH_TOKEN=\"$(<\"${cfg.authTokenFile}\")\"; fi";

  wrapperArgs =
    [ "--set WEB_SEARCH_PERPLEXITY_API_BASE ${lib.escapeShellArg cfg.perplexityApiBase}" ]
    ++ lib.optional (tokenExportCommand != null) "--run ${lib.escapeShellArg tokenExportCommand}";

  wrappedPackage = pkgs.symlinkJoin {
    name = "web-search-cli-wrapped";
    paths = [ inputs.web-search-cli.packages.${pkgs.system}.default ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/web-search ${lib.concatStringsSep " " wrapperArgs}
    '';
  };
in
with lib;
{
  options = {
    defaultConfigs.web-search-cli = {
      enable = mkEnableOption "";

      llmProxy = {
        authTokenFile = mkOption {
          type = types.nullOr types.path;
          default = config.secrets.items.llm-proxy-client-key.target;
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

  config = mkIf isEnabled {
    programs.web-search-cli.enable = true;
    programs.web-search-cli.package = mkDefault wrappedPackage;

    secrets.items.llm-proxy-client-key.target = mkDefault "${config.home.homeDirectory}/.local/state/opencode/api-key";
  };
}
