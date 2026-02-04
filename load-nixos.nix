{ inputs, ... }:
{ machine, system }:
let
  inherit (inputs) nixpkgs home-manager;

  extraModule = {
    home-manager = {
      extraSpecialArgs = {
        inherit inputs;
        systemManager = "home-manager";
      };
    };
  };
in
nixpkgs.lib.nixosSystem rec {
  inherit system;
  modules = [
    machine
    home-manager.nixosModules.home-manager
    extraModule
  ];
  specialArgs = {
    inherit inputs system;
    systemManager = "nixos";
  };
}
