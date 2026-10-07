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
    ../../../modules/home-manager/iamb/default-config.nix
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
    )
    # Fractal is GTK/Linux-only. The Darwin workstations also use this role.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs-unstable.fractal ];

    # Default-enabled on every workstation. A machine where brain does not
    # build can turn it off with a plain `programs.brain.enable = false`.
    programs.brain.enable = lib.mkDefault true;

    # The shared deploy key of surma/brain. modules/home-manager/brain makes
    # git use it in the Brain repo.
    secrets.items.brain-deploy-key.command = ''
      mkdir -p ${config.home.homeDirectory}/.ssh
      install -m 0644 ${../../../assets/ssh-keys/id_brain.pub} ${config.home.homeDirectory}/.ssh/id_brain.pub
      install -m 0600 /dev/null ${config.home.homeDirectory}/.ssh/id_brain
      cat > ${config.home.homeDirectory}/.ssh/id_brain
    '';

    programs.iamb.enable = true;
    defaultConfigs.iamb.enable = true;
  };
}
