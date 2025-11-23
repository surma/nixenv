{
  inputs,
  overlays,
  ...
}:
{ machine, system }:
let
  inherit (inputs) nixpkgs home-manager;
  extraModule =

    {
      nixpkgs.overlays = [
        overlays.unstable
        overlays.extra-pkgs
      ];

      home-manager = {

        sharedModules = [
          {
            nixpkgs.overlays = [
              overlays.extra-pkgs
            ];
          }
        ];
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
