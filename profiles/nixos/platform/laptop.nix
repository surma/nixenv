{
  pkgs,
  ...
}:
# Laptop hardware traits: a touchpad, a fingerprint reader, and a built-in
# keyboard that needs my standard remap. Import it next to ../gui/desktop.nix.
{
  services.libinput.touchpad.disableWhileTyping = true;
  services.fprintd.enable = true;

  # Caps lock becomes escape on tap and meh on hold. Alt and meta swap, so the
  # thumb key matches macOS.
  services.keyd = {
    enable = true;
    treat-as-internal-keyboard = true;
    keyboards."internal" = {
      ids = [ "0001:0001" ];
      settings = {
        main = {
          capslock = "overload(meh, escape)";
          leftalt = "leftmeta";
          leftmeta = "leftalt";
        };
        "meh:C-A-M" = { };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    keyd
  ];
}
