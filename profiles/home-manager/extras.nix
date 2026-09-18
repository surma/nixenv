{
  pkgs,
  inputs,
  ...
}:
# Comfort on top of ./core.nix, for machines whose shell I use every day.
# A bare server (pylon) takes core.nix alone and skips this.
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = with pkgs; [
    btop
    chafa
    dprint
    tailscale
  ];

  customScripts.nix-build-pkg.enable = true;
  customScripts.build-nixpkg-pkg.enable = true;

  programs.yazi.enable = true;
  programs.yazi.enableNushellIntegration = true;
  programs.yazi.shellWrapperName = "y";

  programs.nushell.package = pkgs-unstable.nushell;
}
