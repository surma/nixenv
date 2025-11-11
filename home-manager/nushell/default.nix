{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config.programs) nushell;
in
with lib;
{
  config.programs.nushell = {
    extraConfig = ''
      def ngs [...args] {
        git status --porcelain ...$args | from ssv -n -m 1 | rename status path | update path { [(git rev-parse --show-toplevel) $in] | path join }
      }
    '';
  };
}
