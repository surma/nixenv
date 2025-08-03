{
  nixpkgs,
  home-manager,
  ...
}@inputs:
{ machine, system }:
let
  extraModule =

    {
      # nixpkgs.pks = import nixpkgs {
      #   overlays = [
      #     (final: prev: {
      #       surmtest
      #     })
      #   ]
      # };
      home-manager.extraSpecialArgs = {
        inherit inputs;
        systemManager = "home-manager";
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
