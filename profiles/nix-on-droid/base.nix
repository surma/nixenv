{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.packages = with pkgs; [
    zsh
    helix
    git

  ];

  environment.etcBackupExtension = ".bak";

  user.shell = "${pkgs.zsh}/bin/zsh";

  android-integration = {
    termux-open.enable = true;
    termux-open-url.enable = true;
    termux-setup-storage.enable = true;
    termux-wake-lock.enable = true;
    termux-wake-unlock.enable = true;
    termux-reload-settings.enable = true;
    xdg-open.enable = true;
  };

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  home-manager.config = {
    home.file.".termux/termux.properties".text = ''
      extra-keys = []
    '';
  };
}
