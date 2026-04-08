{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
{
  imports = [
    ../../modules/home-manager/ssh-keys
    ../../modules/home-manager/gpg-keys
  ];

  options.defaultConfigs.agents.enable = mkEnableOption "symlink ~/AGENTS.md to the repo copy";

  config = mkMerge [
    {
      home.sessionVariables = {
        RUSTUP_HOME = "${config.home.homeDirectory}/.rustup";
        CARGO_HOME = "${config.home.homeDirectory}/.cargo";
      };

      home.sessionPath = [ "$CARGO_HOME/bin" ];

      home.packages = (
        with pkgs;
        [
          binaryen
          rustup
          brotli
          cmake
          simple-http-server
          jwt-cli
          graphviz
          hyperfine
          uv
          mprocs
          dua
          wasmtime
        ]
      );
    }

    (mkIf config.defaultConfigs.agents.enable {
      home.file."AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/github.com/surma/nixenv/assets/AGENTS.md";
    })
  ];
}
