{
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  piEnabled = config.programs.pi.enable;
  napkin = inputs.napkin;
in
{
  config = mkIf (systemManager == "home-manager" && piEnabled) {
    home.file.".pi/agent/skills/napkin/SKILL.md".source = "${napkin}/SKILL.md";
  };
}
