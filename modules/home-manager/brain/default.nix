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
    home.packages = [ cfg.package ];

    # Regenerate the agent skill file on every home-manager switch.
    # This keeps the skill file version-matched to the installed brain binary.
    home.activation.brain-skill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} skill write --base "$HOME/.agents"
    '';

    # In the Brain repo, git uses the shared deploy key ~/.ssh/id_brain
    # and does not sign. `brain sync` rebases local commits, and the rebase
    # signs them again when commit.gpgSign is on.
    programs.git.includes = [
      {
        condition = "gitdir:${config.home.homeDirectory}/.local/state/brain/";
        contents = {
          core.sshCommand = "ssh -i ${config.home.homeDirectory}/.ssh/id_brain -o IdentitiesOnly=yes -o IdentityAgent=none";
          commit.gpgSign = false;
          tag.gpgSign = false;
        };
      }
    ];
  };
}
