{
  pkgs,
  ...
}:
# A NixOS machine with a graphical seat that I sit at. Everything here is
# independent of the window manager. The Wayland compositor lives in
# ./hyprland.nix, laptop hardware in ./laptop.nix.
#
# The home-manager counterpart is profiles/home-manager/{fonts,terminal,
# gui-apps}.nix plus a desktop shell profile. Machines import both halves.
{
  imports = [
    ../../modules/nixos/1password-wrapper
  ];

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.seatd.enable = true;
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
  ];

  # Seat, input and media access for the interactive user.
  users.users.surma.extraGroups = [
    "networkmanager"
    "input"
    "video"
    "audio"
    "seat"
    "uinput"
  ];
}
