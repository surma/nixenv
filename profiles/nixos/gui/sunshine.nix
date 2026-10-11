{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# Remote desktop between my Wayland machines. Sunshine streams the desktop
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
    # With autoStart, graphical-session.target starts Sunshine. The GDM
    # greeter's user manager also reaches that target, so Sunshine also
    # starts at the login screen. Machines set autoStart to true to opt in.
    autoStart = lib.mkDefault false;
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

  # Sunshine creates its tray icon only once, at start, so start it after the
  # bar and its tray.
  systemd.user.services.sunshine.after = [ "eww-bar.service" ];

  environment.systemPackages = [ pkgs.moonlight-qt ];

  home-manager.users.surma =
    { config, ... }:
    {
      secrets.items.sunshine-password.target = "${config.home.homeDirectory}/.config/sunshine/password";
    };
}
