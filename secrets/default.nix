{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  secretsConfig = import ./config.nix;

  secretType = types.submodule {
    options = {
      contents = mkOption {
        type = types.path;
      };
      command = mkOption {
        type = types.nullOr types.lines;
        default = null;
      };
      target = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };
in
{
  options = {
    secrets = {
      identity = mkOption {
        type = types.either types.str types.path;
        default = "~/.ssh/id_machine";
      };
      items = mkOption {
        type = types.attrsOf secretType;
        default = { };
      };
    };
  };
  config = {
    home.activation.secrets =
      let
        commands =
          config.secrets.items
          |> lib.attrsToList
          |> lib.map (
            { value, name }:
            let
              secret = secretsConfig.secrets.${name};
              command = if value.command != null then " | (${value.command})" else " > ${value.target}";
            in
            ''
              echo Decrypting ${name}
              cat ${secret.contents} | ${pkgs.age}/bin/age --decrypt -i ${config.secrets.identity} ${command}
            ''
          );
      in
      lib.hm.dag.entryAfter [ "write-boundary" ] (commands |> lib.concatLines);
  };
}
