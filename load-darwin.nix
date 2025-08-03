{
  nixpkgs,
  nix-darwin,
  home-manager,
  overlays,
  ...
}@inputs:
{ machine, system }:
let
  extraModule =
    { config, ... }:
    {
      config = {
        nixpkgs.overlays = [
          overlays.unstable
          overlays.extra-pkgs
        ];

        users.users.${config.system.primaryUser} = {
          name = config.system.primaryUser;
          home = "/Users/${config.system.primaryUser}";
        };

        home-manager = {
          backupFileExtension = "bak";
          extraSpecialArgs = {
            inherit inputs;
            systemManager = "home-manager";
          };
        };
      };
    };
in
nix-darwin.lib.darwinSystem {
  inherit system;
  modules = [
    machine
    home-manager.darwinModules.home-manager
    extraModule
  ];
  specialArgs = {
    inherit inputs system;
    systemManager = "nix-darwin";
  };
}
