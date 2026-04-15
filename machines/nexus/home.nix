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

    secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

    home.stateVersion = "25.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#nexus";
    defaultConfigs.agents.enable = true;
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;

    home.packages = (
      with pkgs;
      [
        gopls
        # clang
        gcc
      ]
    );
    programs.go.enable = true;

    defaultConfigs.pi.extensions.proxy.enable = true;
    defaultConfigs.helix.enableSlSyntax = true;
    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
  };
}
