{
  config,
  lib,
  systemManager,
  ...
}:
with lib;
let
  isEnabled = config.programs.pi.extensions.plan-mode.enable;
  piEnabled = config.programs.pi.enable;
in
{
  options = {
    programs.pi.extensions.plan-mode.enable = mkEnableOption "Pi plan-mode extension";
  };

  config = mkIf (systemManager == "home-manager" && piEnabled && isEnabled) {
    home.file.".pi/agent/extensions/claude-plan-mode.ts".source = ./claude-plan-mode.ts;
  };
}
