{
  pkgs,
  ...
}:
# A NixOS machine with a graphical seat that I sit at. Everything here is
# independent of the window manager. The Wayland compositor lives in
# ./wayland.nix, laptop hardware in ../platform/laptop.nix.
#
# The home-manager counterpart is profiles/home-manager/gui/{fonts,terminal,
# gui-apps}.nix plus a desktop shell profile. Machines import both halves.
{
  imports = [
    ../../../modules/nixos/1password-wrapper
  ];

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  # Discover AirPlay speakers as PipeWire output devices.
  services.avahi.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    raopOpenFirewall = true;
    extraConfig.pipewire."50-raop" = {
      "context.modules" = [
        { name = "libpipewire-module-raop-discover"; }
      ];
    };
    # WirePlumber lists all AirPlay sinks, but it uses one only when I select
    # it. The script describes the rules.
    wireplumber.extraScripts."airplay-manual-only.lua" =
      builtins.readFile ./airplay-manual-only.lua;
    wireplumber.extraConfig."50-airplay-manual-only" = {
      "wireplumber.components" = [
        {
          name = "airplay-manual-only.lua";
          type = "script/lua";
          provides = "custom.airplay-manual-only";
        }
      ];
      "wireplumber.profiles".main."custom.airplay-manual-only" = "required";
    };
  };
  # Each AirPlay sink costs PipeWire about 12 file descriptors. An office
  # network has more receivers than the default limit of 1024 allows, and
  # then PipeWire cannot create the local devices.
  systemd.user.services.pipewire.serviceConfig.LimitNOFILE = 65536;

  # Do not enable seatd. GDM controls the VTs through logind, and libseat
  # picks seatd over logind when seatd runs. Two seat managers then reset the
  # same VT at logout, and the screen can stay blank.
  security.polkit.enable = true;
  services.udisks2.enable = true;

  # Secret Service (org.freedesktop.secrets). GDM's gdm-password PAM service
  # substacks `login`, whose keyring hook the module enables, so the keyring
  # unlocks at login automatically.
  services.gnome.gnome-keyring.enable = true;

  programs.firefox.enable = true;

  # 1Password holds the SSH keys, so it belongs on every seat.
  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "surma" ];
  allowedUnfreeApps = [
    "1password"
    "1password-cli"
  ];

  environment.systemPackages = with pkgs; [
    pavucontrol
    seahorse
  ];

  # Input and media access for the interactive user.
  users.users.surma.extraGroups = [
    "networkmanager"
    "input"
    "video"
    "audio"
    "uinput"
  ];
}
