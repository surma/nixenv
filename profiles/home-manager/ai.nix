{ ... }:
{
  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;

  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;

  programs.agent-browser.enable = true;

  defaultConfigs.pi.settings.enableSkillCommands = true;

  agent.skills = [
    ../../assets/skills/brainstorming
    ../../assets/skills/planning
    ../../assets/skills/debugging
    ../../assets/skills/review
    ../../assets/skills/selfreview
    ../../assets/skills/surma-writer
    ../../assets/skills/rust
    ../../assets/skills/triple-helix
    ../../assets/skills/team-lead
    ../../assets/skills/preact-signals
    ../../assets/skills/web-development
  ];
}
