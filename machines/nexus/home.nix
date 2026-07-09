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
    secrets.items.huggingface-token.target = "${config.home.homeDirectory}/.config/nixenv/huggingface-token";

    home.stateVersion = "25.05";
    defaultConfigs.agents.enable = true;
    agent.skills = [ ../../assets/skills/team-lead ];
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;
    customScripts.transcribe.enable = true;

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
    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
  };
}
