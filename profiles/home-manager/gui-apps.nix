{
  pkgs,
  inputs,
  ...
}:
# Graphical applications that every machine with a GUI gets, on both Linux
# and macOS. Fonts, the terminal and the editor still live in graphical.nix.
{
  config = {
    home.packages = [
      # Flake package: a Linux binary on Linux, ZapFast.app on Darwin.
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.zapfast
    ];
  };
}
