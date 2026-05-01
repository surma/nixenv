{ ... }:
{
  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;

  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;

  programs.agent-browser.enable = true;

  # rtk binary on PATH; the matching pi extension lives in pi-config:
  # https://github.com/surma/pi-config/blob/main/extensions/rtk.ts
  programs.rtk.enable = true;

  agent.skills = [
    ../../assets/skills/brainstorming
    ../../assets/skills/planning
    ../../assets/skills/debugging
    ../../assets/skills/surma-writer
  ];
}
