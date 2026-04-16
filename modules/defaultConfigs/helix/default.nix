{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.defaultConfigs.helix;
  slTreeSitter =
    if cfg.enableSlSyntax then
      inputs.sl2.packages.${pkgs.stdenv.hostPlatform.system}.tree-sitter-sl
    else
      null;
in
{
  options.defaultConfigs.helix = {
    enable = mkEnableOption "default helix configuration";
    enableSlSyntax = mkEnableOption "SL language support (requires sl2 flake input)";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      programs.helix = import ./config.nix {
        inherit lib pkgs;
        inherit slTreeSitter;
        enableSlSyntax = cfg.enableSlSyntax;
      };
    }

    (mkIf cfg.enableSlSyntax {
      home.file.".config/helix/runtime/queries/sl/highlights.scm".source =
        "${slTreeSitter}/queries/highlights.scm";
    })
  ]);
}
