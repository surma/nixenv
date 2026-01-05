{
  config,
  lib,
  ...
}:
with lib;
let
  mutableFiles = config.home.file |> filterAttrs (n: f: f.enable && f.mutable);
in
{
  options.home.file = mkOption {
    type = types.attrsOf (
      types.submodule {
        options.mutable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            If true, the file will be copied instead of symlinked,
            making it writable. The file is overwritten on each
            home-manager activation.
          '';
        };
      }
    );
  };

  config = {
    home.activation.mutableFiles = hm.dag.entryAfter [ "linkGeneration" ] (
      mutableFiles
      |> mapAttrsToList (
        name: file: ''
          $DRY_RUN_CMD rm -f "$HOME/${file.target}"
          $DRY_RUN_CMD cp "${file.source}" "$HOME/${file.target}"
          $DRY_RUN_CMD chmod u+w "$HOME/${file.target}"
        ''
      )
      |> concatStringsSep "\n"
    );
  };
}
