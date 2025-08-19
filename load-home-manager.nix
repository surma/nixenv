{ inputs,... }:
{ system, machine }:
let
  inherit (inputs) home-manager nixpkgs agenix;
  pkgs = nixpkgs.legacyPackages.${system};

in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  modules = [
    agenix.homeManagerModules.default
    machine
  ];

  extraSpecialArgs = {
    inherit inputs system;
    systemManager = "home-manager";
  };
}
