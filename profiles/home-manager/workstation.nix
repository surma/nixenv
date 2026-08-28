{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/home-manager/ssh-keys
    ../../modules/home-manager/gpg-keys
    ../../modules/home-manager/brain
  ];

  config = {
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
        # Graphviz ships its own `gc`, which collides with the `gc` git-commit
        # wrapper from `customScripts`. Let the wrapper win.
        (lib.lowPrio graphviz)
        hyperfine
        uv
        mprocs
        dua
        wasmtime
      ]
    );

    programs.brain.enable = true;
  };
}
