{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  cfg = config.programs.brain;
in
{
  options.programs.brain = {
    enable = mkEnableOption "Brain knowledge base skill file management";
    package = mkOption {
      type = types.package;
      default = inputs.brain.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The brain package to use";
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ (lib.setPriority 4 cfg.package) ];

    # Regenerate the agent skill file on every home-manager switch.
    # This keeps the skill file version-matched to the installed brain binary.
    home.activation.brain-skill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} skill write --base "$HOME/.agents/skills"
    '';
  };
}
