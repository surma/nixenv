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
    ../../modules/home-manager/brain
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

      programs.brain.enable = true;
    }

    (mkIf config.defaultConfigs.agents.enable {
      home.file."AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/github.com/surma/nixenv/assets/AGENTS.md";
    })
  ];
}
