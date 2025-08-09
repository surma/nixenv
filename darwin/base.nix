{
  pkgs,
  system,
  lib,
  ...
}@args:
{

  nixpkgs.config.allowUnfree = true;

  nix.enable = true;

  nix.settings.experimental-features = "nix-command flakes pipe-operators";

  fonts.packages = with pkgs; [ fira-code ];

  security.pam.services.sudo_local.touchIdAuth = true;

  homebrew = {
    enable = true;
    casks = [
      "arc"
      "barrier"
      # "nvidia-geforce-now"
      "slack"
      "zulip"
      "android-file-transfer"
      "nightfall"
      "karabiner-elements"
    ];
  };

  # networking.computerName = "";
  # networking.hostName = "";

  system.primaryUser = "surma";

  system.defaults = {
    NSGlobalDomain = {
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
    };
    WindowManager = {
      StandardHideDesktopIcons = true;
    };
    dock = {
      appswitcher-all-displays = true;
      autohide = true;
      autohide-time-modifier = 0.1;
      persistent-apps = [ ];
      persistent-others = [ "~/" ];
      show-recents = false;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
    };
    menuExtraClock = {
      Show24Hour = true;
      ShowDate = 1;
      ShowDayOfMonth = true;
      ShowDayOfWeek = true;
      ShowSeconds = false;
    };
    screencapture = {
      disable-shadow = true;
      type = "png";
    };
  };
}
