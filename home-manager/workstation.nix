{
  config,
  pkgs,
  ...
}:
let
  inherit (pkgs) callPackage;
in
{

  imports = [
    ./ssh-keys.nix
    ./gpg-keys.nix

  ];

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
      just
    ]
  );
}
