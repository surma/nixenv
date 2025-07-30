{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../home-manager/unfree-apps.nix
    ./surmrock-hardware.nix
    inputs.home-manager.nixosModules.home-manager
    ../nixos/base.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "surmrock";
  networking.networkmanager.enable = true;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  users.users.surma = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBpQAnBfVN7zfxxPQpIl8ZKII6cKVaHdBMnwi2aH5uApr313bD+3fi9SXkV8E+5X+MwQIaXs+fzEDifrDCsGhegC9Nedt0wGwcV84mjqXEy/8hzsMkO1bKX7i6i2wUaWasfG/kyC8/eJGoGmhZ27Wq7tPlzBRUgp9fzjXtpMlUXoLKnc7gU1soKdtEfBSZeh0pyUL8DTDVKvnzfAF0yKqV2qjyymwIf6LTQ3gWaHCY6neM/ROE0iGuFcYnCU9dEiyH59NBEiXvekA/mjPdJB9hMWgjcnuikj1A/iNiKkroMI3ky+GDiRomnRjnrTjSIvmhG6WuXb1gTspnZbyDjj5r"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjljY7ksA49iEa/okN+JeqBTHUAVZ9Sr9Zu5fWqCt2N"
    ];
  };

  home-manager.users.surma =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../home-manager/claude-code

        ../home-manager/base.nix
        ../home-manager/dev.nix
        ../home-manager/nixdev.nix
        ../home-manager/linux.nix
        ../home-manager/workstation.nix

        ../home-manager/unfree-apps.nix
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

        programs.claude-code.enable = true;
        defaultConfigs.claude-code.enable = true;
      };
    };

  services.openssh.enable = true;

  system.stateVersion = "25.05";
}
