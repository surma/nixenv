{
  pkgs,
  inputs,
  ...
}:
# Graphical applications that every machine with a GUI gets, on both Linux and
# macOS. Fonts live in ./fonts.nix, the terminal in ./terminal.nix.
{
  config = {
    allowedUnfreeApps = [
      "vscode"
    ];
    home.packages = [
      pkgs.vscode
      # Flake package: a Linux binary on Linux, ZapFast.app on Darwin.
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.zapfast
    ];
  };
}
