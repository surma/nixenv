{
  pkgs,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
in

{

  imports = [
    ./unfree-apps.nix

    ./wezterm
  ];

  config = {
    allowedUnfreeApps = [
      "vscode"
    ];
    home.packages = (
      with pkgs;
      [
        fira-code
        roboto
        font-awesome
        vscode
      ]
    );

    programs.wezterm.enable = true;
    programs.wezterm.package = pkgs-unstable.wezterm;
    defaultConfigs.wezterm.enable = true;
  };
}
