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
  # A switch does not restart GDM, so GDM keeps the session file of the
  # generation that it started with. With a store path in Exec, it then starts
  # an old sxwm-session against the new user units. The path in the system
  # profile always gives the current sxwm-session.
  sxwmSession = pkgs.runCommand "sxwm-session-file" { passthru.providedSessions = [ "sxwm" ]; } ''
    mkdir -p $out/share/wayland-sessions
    substitute ${sxwm}/share/wayland-sessions/sxwm.desktop \
      $out/share/wayland-sessions/sxwm.desktop \
      --replace-fail ${sxwm}/bin/sxwm-session /run/current-system/sw/bin/sxwm-session
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
