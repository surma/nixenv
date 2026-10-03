{
  pkgs,
  lib,
  ...
}:
# Laptop hardware traits: a touchpad, a fingerprint reader, and a built-in
# keyboard that needs my standard remap. Import it next to ../gui/desktop.nix.
{
  services.libinput.touchpad.disableWhileTyping = true;
  services.fprintd.enable = true;
  services.power-profiles-daemon.enable = true;

  # Closing the lid suspends to RAM, then hibernates after 30 minutes. Recent
  # laptops only offer s2idle (`cat /sys/power/mem_sleep`), not S3, so a closed
  # lid keeps drawing power until the machine writes an image to disk.
  #
  # On AC it only suspends, and systemd ignores the lid entirely while docked
  # to an external display (HandleLidSwitchDocked defaults to ignore), so a
  # closed-lid desktop setup keeps working.
  #
  # Hibernation needs `boot.resumeDevice` per machine: the swap has to be at
  # least as large as RAM, and its LUKS container has to be opened by the
  # initrd. Without that the image is written but never restored.
  services.logind = {
    lidSwitch = lib.mkDefault "suspend-then-hibernate";
    lidSwitchExternalPower = lib.mkDefault "suspend";
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # Caps lock becomes escape on tap and meh on hold. Alt and meta swap, so the
  # thumb key matches macOS.
  #
  # Both shift keys are one-shot: a tap shifts the next key, and a hold works
  # as usual. This keyboard cannot report caps lock, left shift, and a third
  # key at the same time, so a tap avoids that combination. A tap expires
  # after one second.
  services.keyd = {
    enable = true;
    treat-as-internal-keyboard = true;
    keyboards."internal" = {
      ids = [ "0001:0001" ];
      settings = {
        global.oneshot_timeout = 1000;
        main = {
          capslock = "overload(meh, escape)";
          leftalt = "leftmeta";
          leftmeta = "leftalt";
          leftshift = "oneshot(shift)";
          rightshift = "oneshot(shift)";
        };
        "meh:C-A-M" = { };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    keyd
  ];
}
