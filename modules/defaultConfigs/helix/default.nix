{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  slTreeSitter = inputs.sl2.packages.${pkgs.system}.tree-sitter-sl;
in
{
  options.defaultConfigs.helix.enable = mkEnableOption "default helix configuration";

  config = mkIf config.defaultConfigs.helix.enable {
    programs.helix = import ./config.nix { inherit pkgs inputs; };

    home.file.".config/helix/runtime/queries/sl/highlights.scm".source =
      "${slTreeSitter}/queries/highlights.scm";
  };
}
