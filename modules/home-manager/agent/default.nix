{
  config,
  lib,
  ...
}:
let
  cfg = config.agent;
in
with lib;
{
  options.agent = {
    skills = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "List of skill directories (each containing a SKILL.md) to symlink into ~/.agents/skills/";
    };
  };

  config = mkIf (cfg.skills != [ ]) {
    home.file = builtins.listToAttrs (
      builtins.map (skillPath: {
        name = ".agents/skills/${builtins.unsafeDiscardStringContext (builtins.baseNameOf skillPath)}";
        value.source = skillPath;
      }) cfg.skills
    );
  };
}
