{
  # WiFi stability improvements for mesh networks
  boot.extraModprobeConfig = ''
    options mt7925e disable_aspm=1
  '';

  networking.networkmanager.settings = {
    wifi = {
      roam-threshold = "-60";
      fast-transition = "false";
      scan-rand-mac-address = "false";
    };
  };

  # Conservative WiFi power management
  services.tlp.settings = {
    WIFI_PWR_ON_AC = "off";
    WIFI_PWR_ON_BAT = "on";
  };

}
