{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# Remote desktop between my Hyprland machines. Sunshine streams the desktop
# of this machine, and Moonlight shows the desktop of another machine.
# Import it next to ./wayland.nix.
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  sunshine = lib.getExe config.services.sunshine.package;
in
{
  services.sunshine = {
    enable = true;
    package = pkgs-unstable.sunshine;
    # The NixOS module's generic graphical-session.target also runs in the
    # GDM greeter's user manager. Start Sunshine from the Hyprland-only target
    # below instead.
    autoStart = false;
    openFirewall = true;
    settings = {
      capture = "wlr";
      origin_web_ui_allowed = "wan";
    };
  };

  # Sunshine keeps the web UI login in its state file. Write the login from
  # the secret before each start, so the web UI never asks for a new login.
  # `--creds` keeps the rest of the state file, which holds the pairings.
  # The password is visible in the process arguments for a moment.
  systemd.user.services.sunshine.serviceConfig.ExecStartPre =
    pkgs.writeShellScript "sunshine-credentials" ''
      exec ${sunshine} --creds surma "$(< "$HOME/.config/sunshine/password")"
    '';

  environment.systemPackages = [ pkgs.moonlight-qt ];

  home-manager.users.surma =
    { config, osConfig, ... }:
    {
      secrets.items.sunshine-password.target = "${config.home.homeDirectory}/.config/sunshine/password";

      # Sunshine must follow the actual Hyprland session, not the generic
      # graphical-session.target that GDM also exposes to its greeter user.
      # The NixOS Sunshine unit remains the single service definition; this
      # target dependency supplies the Hyprland-only autostart edge.
      systemd.user.targets."hyprland-session" = lib.mkIf (osConfig.gui.compositor == "hyprland") {
        Unit.Wants = [ "sunshine.service" ];
      };
    };
}
