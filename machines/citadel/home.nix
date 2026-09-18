{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/core.nix
    ../../profiles/home-manager/extras.nix
    ../../profiles/home-manager/roles/dev.nix
    ../../profiles/home-manager/roles/nixdev.nix
    ../../profiles/home-manager/platform/linux.nix
    ../../profiles/home-manager/roles/workstation.nix
    ../../profiles/home-manager/roles/ai.nix
    ../../profiles/home-manager/roles/go.nix
  ];

  config = {
    secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";
    secrets.items.scout-gws-credentials.target = "${config.home.homeDirectory}/.local/state/gws-credentials";
    secrets.items.huggingface-token.target = "${config.home.homeDirectory}/.config/nixenv/huggingface-token";

    home.sessionVariables.GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND = "file";
    home.sessionVariables.GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE =
      config.secrets.items.scout-gws-credentials.target;

    home.stateVersion = "25.05";

    programs.gitea-cli.enable = true;
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;
    customScripts.transcribe.enable = true;

    home.packages = (
      with pkgs;
      [
        inputs.gws.packages.${pkgs.stdenv.hostPlatform.system}.default
        gcc
      ]
    );

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
  };
}
