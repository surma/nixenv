{
  config,
  lib,
  systemManager,
  ...
}:
with lib;
let
  piEnabled = config.programs.pi.enable;
in
{
  config = mkIf (systemManager == "home-manager" && piEnabled) {
    home.file.".pi/agent/skills/napkin/SKILL.md".source = ./SKILL.md;
  };
}
