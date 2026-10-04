{
  config,
  pkgs,
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
    secrets.items.huggingface-token.target = "${config.home.homeDirectory}/.config/nixenv/huggingface-token";

    home.stateVersion = "25.05";
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.transcribe.enable = true;

    agent.skills = [
      ../../assets/skills/orchestrator
      ../../assets/skills/subagent
    ];

    home.packages = (
      with pkgs;
      [
        # clang
        gcc
      ]
    );

    defaultConfigs.pi.extensions.proxy.enable = true;

    # Headless: no desktop for the herdr GUI.
    programs.herdr.gui.enable = false;
  };
}
