{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/ai.nix
  ];

  config = {
    allowedUnfreeApps = [
      "claude-code"
    ];

    sops.validateSopsFiles = false;
    sops.secrets.llm-proxy-client-key = {
      sopsFile = ../../secrets/shared/llm-proxy-client-key.yaml;
      path = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";
      mode = "0600";
    };

    defaultConfigs.pi.llmProxy.apiKeyFile = config.sops.secrets.llm-proxy-client-key.path;
    defaultConfigs.opencode.llmProxy = {
      manageSecret = false;
      apiKeyFile = config.sops.secrets.llm-proxy-client-key.path;
    };
    defaultConfigs.web-search-cli.llmProxy = {
      manageSecret = false;
      authTokenFile = config.sops.secrets.llm-proxy-client-key.path;
    };

    home.stateVersion = "25.05";

    defaultConfigs.agents.enable = true;
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;

    home.packages = (
      with pkgs;
      [
        gopls
        gcc
      ]
    );
    programs.go.enable = true;

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    defaultConfigs.helix.enableSlSyntax = true;
    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
  };
}
