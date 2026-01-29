{ lib, config, pkgs, systemManager, ... }:
let
  inherit (lib) mkOption mkIf types;
in
{
  options.allowedUnfreeApps = mkOption {
    type = types.listOf types.str;
    default = [];
    description = "List of unfree package names to allow";
  };

  config = {
    nixpkgs.config.allowUnfreePredicate =
      pkg: lib.lists.elem (lib.getName pkg) config.allowedUnfreeApps;
  };
}
