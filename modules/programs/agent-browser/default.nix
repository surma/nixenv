{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
{
  options = {
    programs.agent-browser = {
      enable = mkEnableOption "agent-browser";
      package = mkOption {
        type = types.package;
        default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser;
        description = "The agent-browser package to use";
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && config.programs.agent-browser.enable) {
    home.packages = [ config.programs.agent-browser.package ];
    agent.skills = [ "${config.programs.agent-browser.package}/share/pi/skills/agent-browser" ];
    home.sessionVariables.AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe (
      if pkgs.stdenv.isDarwin then pkgs.google-chrome else pkgs.chromium
    );
  };
}
