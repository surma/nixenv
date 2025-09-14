{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{

  imports = [
    ../secrets
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
    "pipe-operators"
  ];

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  programs.nix-ld.enable = true;
  security.rtkit.enable = true;

  programs.git.enable = true;
  programs.zsh.enable = true;
  services.openssh.enable = true;

  users.defaultUserShell = pkgs.zsh;
  users.users.surma = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = with config.secrets.keys; [
      surma
    ];
  };
}
