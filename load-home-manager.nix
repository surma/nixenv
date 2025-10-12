{ inputs, ... }:
{ system, machine }:
let
  inherit (inputs) home-manager;

  pkgs = nixpkgs.legacyPackages.${system};
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  modules = [ machine ];

  extraSpecialArgs = {
    inherit inputs system;
    systemManager = "home-manager";
  };
}
