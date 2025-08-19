{
  inputs,
  overlays,
  ...
}:
{ machine, system }:
let
  inherit (inputs) nixpkgs home-manager agenix;
  extraModule =

    {
      nixpkgs.overlays = [
        overlays.unstable
        overlays.extra-pkgs
      ];

      home-manager = {
        sharedModules = [
          agenix.homeManagerModules.default
          {
            nixpkgs.overlays = [
              overlays.unstable
              overlays.extra-pkgs
            ];
          }
        ];
        extraSpecialArgs = {
          inherit inputs system;
          systemManager = "home-manager";
        };
      };
    };
in
nixpkgs.lib.nixosSystem rec {
  inherit system;
  modules = [
    machine
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    extraModule
  ];
  specialArgs = {
    inherit inputs system;
    systemManager = "nixos";
  };
}
