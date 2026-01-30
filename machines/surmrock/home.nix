{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/home-manager/opencode

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix

  ];

  config = {
    allowedUnfreeApps = [
      "claude-code"
    ];

    home.packages = (
      with pkgs;
      [
      ]
    );

    home.stateVersion = "25.05";

    home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmrock";

    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
    defaultConfigs.claude-code.enable = true;
  };
};

  networking.firewall.enable = false;

  services.openssh.enable = true;

  system.stateVersion = "25.05";
