{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# SXWM-specific system settings for profiles/nixos/gui/wayland.nix.
let
  sxwm = inputs.sxwm.packages.${pkgs.stdenv.hostPlatform.system}.sxwm;
  # GDM looks up the TryExec command of a session file in its own PATH,
  # which does not contain the system profile. The upstream sxwm.desktop
  # names sxwm-session without a path, so GDM rejects the session.
  sxwmSession = pkgs.runCommand "sxwm-session-file" { passthru.providedSessions = [ "sxwm" ]; } ''
    mkdir -p $out/share/wayland-sessions
    substitute ${sxwm}/share/wayland-sessions/sxwm.desktop \
      $out/share/wayland-sessions/sxwm.desktop \
      --replace-fail sxwm-session ${sxwm}/bin/sxwm-session
  '';
in
{
  imports = [ inputs.sxwm.nixosModules.default ];

  config = lib.mkIf (config.gui.compositor == "sxwm") {
    programs.sxwm.enable = true;
    # See the same setting in ./niri.nix.
    services.displayManager.defaultSession = "sxwm";
    # Use sxwmSession in place of the session package of the SXWM module.
    services.displayManager.sessionPackages = lib.mkForce [ sxwmSession ];
    # SXWM starts xwayland-satellite from PATH when the first X11 client
    # connects.
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
