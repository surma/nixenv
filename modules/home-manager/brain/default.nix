{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.programs.brain;
in
{
  options.programs.brain = {
    enable = mkEnableOption "Brain knowledge base skill file management";
  };

  config = mkIf cfg.enable {
    # Regenerate the agent skill file on every home-manager switch.
    # This keeps the skill file version-matched to the installed brain binary.
    home.activation.brain-skill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v brain >/dev/null 2>&1; then
        run brain skill write --base "$HOME/.agents/skills"
      fi
    '';
  };
}
