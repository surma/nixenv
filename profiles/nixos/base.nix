{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{

  imports = [
    # ../../modules/secrets  # Now injected globally via features/secrets.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
    "pipe-operators"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # The NixOS secrets service runs as root, so the module default of
  # `~/.ssh/id_machine` would expand to /root/.ssh/id_machine. Name the real
  # key instead.
  secrets.identity = lib.mkDefault "/home/surma/.ssh/id_machine";

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

  environment.systemPackages = with pkgs; [
    nftables
    helix
    zellij
    nushell
  ];

  programs.nix-ld.enable = true;
  security.rtkit.enable = true;

  programs.git.enable = true;
  programs.zsh.enable = true;
  services.openssh.enable = true;
  programs.mosh.enable = true;
  services.openssh.settings.AcceptEnv = [
    "COLORTERM"
    "TERM_PROGRAM"
  ];

  users.defaultUserShell = pkgs.zsh;
  users.users.surma = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = with config.secrets.keys; [
      surma
    ];
  };
}
