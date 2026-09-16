{
  config,
  ...
}:
{
  imports = [
    ../../modules/home-manager/herdr
  ];

  # Installs herdr and regenerates ~/.agents/skills/herdr/SKILL.md from
  # `herdr --skill` on every switch, so the skill matches the binary.
  programs.herdr.enable = true;

  # Managed values from the live ~/.config/herdr/config.toml, plus keyboard
  # navigation bindings for the Choc NAV layer (W/R cycle workspaces, S/F
  # cycle tabs; direct chords, no prefix). Reload applies without restart:
  # `herdr server reload-config`.
  programs.herdr.settings = {
    onboarding = false;
    theme = {
      name = "gruvbox";
      auto_switch = false;
    };
    ui = {
      status_indicators = "symbols";
      sound.enabled = false;
      toast.delivery = "system";
    };
    keys = {
      previous_workspace = "alt+left";
      next_workspace = "alt+right";
      previous_tab = "ctrl+shift+tab";
      next_tab = "ctrl+tab";
    };
  };

  defaultConfigs.agents.enable = true;

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  secrets.items.openrouter-api-key.target = "${config.home.homeDirectory}/.local/state/openrouter-api-key";
  defaultConfigs.pi.openRouter.keyFile = config.secrets.items.openrouter-api-key.target;

  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;

  programs.agent-browser.enable = true;

  defaultConfigs.pi.settings.enableSkillCommands = true;

  # Compaction. Replaces the hand-off pipeline that used to live in pi-config:
  # pi-vcc builds its summary by extraction rather than asking the model to
  # write one, so it needs no output budget at the point where context is
  # already full.
  defaultConfigs.pi.extraPackages = [ "npm:@sting8k/pi-vcc" ];

  agent.skills = [
    # ../../assets/skills/brainstorming
    # ../../assets/skills/planning
    # ../../assets/skills/debugging
    ../../assets/skills/simplify
    ../../assets/skills/surma-writer
    ../../assets/skills/rust
    ../../assets/skills/triple-helix
    ../../assets/skills/preact-signals
    ../../assets/skills/web-development
    ../../assets/skills/bro
  ];
}
