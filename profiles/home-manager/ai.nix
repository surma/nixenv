{ config, ... }:
{
  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  secrets.items.openrouter-api-key.target =
    "${config.home.homeDirectory}/.local/state/openrouter-api-key";
  defaultConfigs.pi.openRouter.keyFile = config.secrets.items.openrouter-api-key.target;

  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;

  programs.agent-browser.enable = true;

  defaultConfigs.pi.settings.enableSkillCommands = true;

  agent.skills = [
    ../../assets/skills/brainstorming
    ../../assets/skills/planning
    ../../assets/skills/debugging
    ../../assets/skills/surma-writer
    ../../assets/skills/rust
    ../../assets/skills/triple-helix
    ../../assets/skills/team-lead
    ../../assets/skills/orchestrator
    ../../assets/skills/preact-signals
    ../../assets/skills/web-development
    ../../assets/skills/bro
  ];
}
