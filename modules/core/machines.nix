{
  lib,
  config,
  inputs,
  ...
}:
{
  config = {
    # NixOS machines
    nixosConfigurations =
      lib.optionalAttrs (builtins.pathExists /etc/nixos/hardware-configuration.nix) {
        generic-nixos.imports = [ ../../machines/generic-nixos ];
        generic-nixos-laptop.imports = [ ../../machines/generic-nixos-laptop ];
      }
      // {
        archon.imports = [ ../../machines/archon ];
        citadel.imports = [ ../../machines/citadel ];
        dark-archon.imports = [ ../../machines/dark-archon ];
        nexus.imports = [ ../../machines/nexus ];
        pylon.imports = [ ../../machines/pylon ];
        testcontainer.imports = [ ../../machines/testcontainer ];
        surmframework = config.nixosConfigurations.archon;
        surmedge = config.nixosConfigurations.pylon;
      };

    # Darwin machines
    darwinConfigurations = {
      generic-darwin.imports = [ ../../machines/generic-darwin ];
      dragoon.imports = [ ../../machines/dragoon ];
      shopisurm.imports = [ ../../machines/shopisurm ];
    };

    # Home-manager standalone configs
    homeConfigurations = {
      generic-linux.imports = [ ../../machines/generic-linux ];
      generic-linux-arm64.imports = [ ../../machines/generic-linux ];
      assimilator.imports = [ ../../machines/assimilator ];
      forge.imports = [ ../../machines/forge ];
      scout.imports = [ ../../machines/scout ];
    };

    homeConfigurationSystems = {
      generic-linux = "x86_64-linux";
      generic-linux-arm64 = "aarch64-linux";
      assimilator = "aarch64-linux";
      forge = "aarch64-linux";
      scout = "x86_64-linux";
    };
  };

  config.darwinConfigurations = {
    surmbook = config.darwinConfigurations.dragoon;
  };
}
