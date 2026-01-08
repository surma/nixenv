{
  pkgs,
  lib,
  config,
  systemManager,
  ...
}:
with lib;
let
  inherit (pkgs) writeShellApplication;
  secretsConfig = import ./config.nix;

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
    };
  };
in
{
  options = {
    secrets = {
      keys = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
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
  config =
    let
      commands =
        config.secrets.items
        |> lib.attrsToList
        |> lib.map (
          { value, name }:
          let
            secret = secretsConfig.secrets.${name};
            command = if value.command != null then " | (${value.command})" else " > ${value.target}";
            prelude = lib.optionalString (value.target != null) ''
              mkdir -p ${value.target |> builtins.dirOf}
              touch ${value.target}
              chmod 0600 ${value.target}
            '';
          in
          ''
            echo Decrypting ${name}
            ${prelude}
            ${pkgs.age}/bin/age --decrypt -i ${config.secrets.identity} < ${secret.contents} ${command} 
          ''
        )
        |> lib.concatLines;

      writeSecrets = writeShellApplication {
        name = "write-secrets";
        text = commands;
        runtimeInputs = [ pkgs.coreutils ];
      };

      writeTask =
        if systemManager == "home-manager" then
          {
            home.activation.secrets = lib.hm.dag.entryAfter [
              "write-boundary"
            ] ''${writeSecrets}/bin/write-secrets'';
          }
        else if systemManager == "nixos" then
          {
            systemd.services.secrets = {
              serviceConfig = {
                Type = "oneshot";
                ExecStart = ''${writeSecrets}/bin/write-secrets'';
                RemainAfterExit = true; # Remain "active" after completion (optional but common for oneshot)
              };
              wantedBy = [ "multi-user.target" ];
            };

          }
        else if systemManager == "nix-darwin" then
          {
            # Run secrets decryption during activation (darwin-rebuild switch)
            system.activationScripts.postActivation.text = ''
              ${writeSecrets}/bin/write-secrets
            '';
          }
        else
          throw "Secrets not yet supported on ${systemManager}";
    in
    {
      secrets.keys = secretsConfig.keys;
    }
    // writeTask;
}
