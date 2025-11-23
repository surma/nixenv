{ inputs, overlays, ... }:
{ system, machine }:
let
  inherit (inputs) home-manager nixpkgs;

  pkgs = nixpkgs.legacyPackages.${system};

  extraModule =
    { ... }:
    {
      config = {
        nixpkgs.overlays = [
          overlays.extra-pkgs
        ];

      };
    };
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  modules = [
    machine
    extraModule
  ];

  extraSpecialArgs = {
    inherit inputs system;
    systemManager = "home-manager";
  };
}
