{
  config,
  pkgs,
  inputs,
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

    secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";
    secrets.items.scout-gws-credentials.target = "${config.home.homeDirectory}/.local/state/gws-credentials";

    home.sessionVariables.GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND = "file";
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE =
      config.secrets.items.scout-gws-credentials.target;

    home.stateVersion = "25.05";

    defaultConfigs.agents.enable = true;
    programs.gitea-cli.enable = true;
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;

    home.packages = (
      with pkgs;
      [
        inputs.gws.packages.${pkgs.stdenv.hostPlatform.system}.default
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
