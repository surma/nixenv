{ config, lib, ... }:
{

  options = with lib; {
    allowedUnfreeApps = mkOption {
      type = with types; listOf str;
      default = [ ];
    };
  };

  config = {
    nixpkgs.config.allowUnfreePredicate =
      pkg: lib.lists.elem (lib.getName pkg) config.allowedUnfreeApps;
  };

}
