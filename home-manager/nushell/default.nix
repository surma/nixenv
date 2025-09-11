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
  imports = [
  ];

  options = {
    programs.nushell = {
      aliases = mkOption {
        type = types.attrsOf types.lines;
        default = { };
      };
    };
  };
  config.programs.nushell = {
    extraConfig = (
      nushell.aliases
      |> lib.attrsToList
      |> map ({ name, value }: ''alias ${name} = ${value}'')
      |> lib.concatStringsSep "\n"
    );
  };
}
