{
  config,
  ...
}:
{
  imports = [
    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/workstation.nix
  ];

  home.stateVersion = "25.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#citadel";

  programs.opencode.enable = true;
  defaultConfigs.opencode.enable = true;
  defaultConfigs.claude-code.enable = true;
}
