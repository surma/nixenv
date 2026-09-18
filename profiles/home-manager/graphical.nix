{
  pkgs,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in

{

  config = {
    allowedUnfreeApps = [
      "vscode"
    ];
    home.packages =
      (with pkgs; [
        fira-code
        roboto
        font-awesome
        vscode
      ])
      ++ [
        # Flake package: a Linux binary on Linux, ZapFast.app on Darwin.
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.zapfast
      ];

    programs.wezterm.enable = true;
    programs.wezterm.package = pkgs-unstable.wezterm;
    defaultConfigs.wezterm.enable = true;
  };
}
