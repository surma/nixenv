{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ../../../modules/home-manager/ssh-keys
    ../../../modules/home-manager/gpg-keys
    ../../../modules/home-manager/brain
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
        cmake
        simple-http-server
        jwt-cli
        # Graphviz ships its own `gc`, which collides with the `gc` git-commit
        # wrapper from `customScripts`. Let the wrapper win.
        (lib.lowPrio graphviz)
        uv
        mprocs
        dua
        wasmtime
        inputs.m.packages.${pkgs.stdenv.hostPlatform.system}.default
      ]
    );

    # Default-enabled on every workstation. A machine where brain does not
    # build can turn it off with a plain `programs.brain.enable = false`.
    programs.brain.enable = lib.mkDefault true;

    programs.iamb = {
      enable = true;
      package = pkgs-unstable.iamb;
      settings.profiles.user.user_id = "@surma:matrix.surma.technology";
    };
  };
}
