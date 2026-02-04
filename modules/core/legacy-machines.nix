{
  lib,
  config,
  inputs,
  ...
}:
{
  # Temporarily define machines using the old structure
  # This provides a compatibility layer during migration

  config = {
    # NixOS machines
    nixosConfigurations = {
      generic-nixos.imports = [ ../../machines/generic-nixos ];
      archon.imports = [ ../../machines/archon ];
      surmrock.imports = [ ../../machines/surmrock ];
      nexus.imports = [ ../../machines/nexus ];
      pylon.imports = [ ../../machines/pylon ];
      testcontainer.imports = [ ../../machines/testcontainer ];
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
      surmturntable.imports = [ ../../machines/surmturntable ];
    };

    # Android configs
    nixOnDroidConfigurations = {
      generic-android.imports = [ ../../machines/generic-android ];
    };
  };

  # Create aliases directly in the configuration options
  config.nixosConfigurations = {
    surmframework = config.nixosConfigurations.archon;
    surmedge = config.nixosConfigurations.pylon;
  };

  config.darwinConfigurations = {
    surmbook = config.darwinConfigurations.dragoon;
  };
}
