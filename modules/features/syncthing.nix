{ systemManager, ... }:
{
  imports = [
    ../services/syncthing/default-config.nix
  ];
}
