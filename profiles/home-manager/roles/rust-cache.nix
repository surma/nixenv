{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  supported = builtins.hasAttr system inputs.kache.packages;
in
lib.mkIf supported (
  let
    kache = inputs.kache.packages.${system}.default;
  in
  {
    home.packages = [ kache ];

    programs.cargo = {
      enable = true;
      package = null;
      settings.build.rustc-wrapper = "${kache}/bin/kache";
    };
  }
)
