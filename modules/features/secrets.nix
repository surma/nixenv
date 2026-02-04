{
  lib,
  config,
  pkgs,
  systemManager,
  inputs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  secretsConfig = import ../../secrets/config.nix;

  secretType = types.submodule {
    options = {
      command = mkOption {
        type = types.nullOr types.lines;
        default = null;
      };
      target = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      mode = mkOption {
        type = types.str;
        default = "0600";
        description = "File permissions (octal mode)";
        example = "0644";
      };
    };
  };

  # Helper to create the secrets activation script
  mkSecretsHelper =
    { secretsItems, identity }:
    let
      commands =
        secretsItems
        |> lib.attrsToList
        |> lib.map (
          { value, name }:
          let
            secret = secretsConfig.secrets.${name};
            command = if value.command != null then " | (${value.command})" else " > ${value.target}";
            prelude = lib.optionalString (value.target != null) ''
              mkdir -p ${value.target |> builtins.dirOf}
              touch ${value.target}
              chmod ${value.mode} ${value.target}
            '';
          in
          ''
            echo Decrypting ${name}
            ${prelude}
            ${pkgs.age}/bin/age --decrypt -i ${identity} < ${secret.contents} ${command}
          ''
        )
        |> lib.concatLines;

      writeSecrets = pkgs.writeShellApplication {
        name = "write-secrets";
        text = commands;
        runtimeInputs = [ pkgs.coreutils ];
      };
    in
    writeSecrets;

  writeSecretsScript = mkSecretsHelper {
    secretsItems = config.secrets.items;
    identity = config.secrets.identity;
  };

  # System-specific activation based on systemManager
  activationConfig =
    if systemManager == "home-manager" then
      {
        home.activation.secrets = mkIf (config.secrets.items != { }) (
          lib.hm.dag.entryAfter [
            "write-boundary"
          ] "${writeSecretsScript}/bin/write-secrets"
        );
      }
    else if systemManager == "nixos" then
      {
        systemd.services.secrets = mkIf (config.secrets.items != { }) {
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${writeSecretsScript}/bin/write-secrets";
            RemainAfterExit = true;
          };
          wantedBy = [ "multi-user.target" ];
        };
      }
    else if systemManager == "nix-darwin" then
      {
        system.activationScripts.postActivation.text = mkIf (config.secrets.items != { }) ''
          ${writeSecretsScript}/bin/write-secrets
        '';
      }
    else
      throw "Secrets not yet supported on ${systemManager}";
in
{
  options.secrets = {
    keys = mkOption {
      type = types.attrsOf types.str;
      default = secretsConfig.keys;
      description = "Age encryption keys";
    };

    identity = mkOption {
      type = types.either types.str types.path;
      default = "~/.ssh/id_machine";
      description = "Path to the age identity file";
    };

    items = mkOption {
      type = types.attrsOf secretType;
      default = { };
      description = "Secrets to decrypt";
    };
  };

  config = activationConfig;
}
