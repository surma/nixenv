{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  cfg = config.programs.herdr;

  # `herdr --skill` prints the agent skill that belongs to the binary it was
  # printed by, so generating it here keeps the documented CLI surface from
  # drifting away from the installed herdr. Written atomically, and only when
  # the command produced something, so a failure leaves the previous skill in
  # place instead of truncating it.
  writeSkill = pkgs.writeShellScript "herdr-write-skill" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    target="$HOME/.agents/skills/herdr"
    mkdir -p "$target"

    tmp="$(mktemp "$target/.SKILL.md.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    ${lib.getExe' cfg.package "herdr"} --skill > "$tmp"
    [ -s "$tmp" ]
    mv "$tmp" "$target/SKILL.md"
  '';
in
{
  imports = [
    ./default-config.nix
  ];

  options.programs.herdr = {
    enable = mkEnableOption "Herdr terminal workspace manager for coding agents";
    package = mkOption {
      type = types.package;
      default = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The herdr package to use";
    };
    gui = {
      enable = mkEnableOption "Herdr GPUI, the native desktop client for herdr (Linux only)";
      package = mkOption {
        type = types.package;
        default = inputs.herdr-gpui.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = literalExpression "inputs.herdr-gpui.packages.\${system}.default";
        description = "The herdr-gpui package to use";
      };
    };
    server.enable = mkEnableOption ''
      a systemd user service for the herdr server (Linux only). The server then
      lives in its own cgroup, so a restart of the graphical session does not
      kill it and its panes. Enable linger to keep it running after logout'';
    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Settings written to ~/.config/herdr/config.toml. Empty by default,
        which skips generating the file so herdr keeps its own defaults.'';
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    assertions = [
      {
        assertion = cfg.gui.enable -> pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.herdr.gui: the herdr-gpui flake builds only for Linux. On macOS, use the Homebrew cask.";
      }
      {
        assertion = cfg.server.enable -> pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.herdr.server: the service needs systemd, so it works only on Linux.";
      }
    ];

    systemd.user.services.herdr = mkIf cfg.server.enable {
      Unit = {
        Description = "herdr server";
        # A restart kills every pane process. Keep the old server on a switch.
        # `herdr status` then reports a stale server binary, and you restart
        # the service when it suits you.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        # Panes inherit the environment of the server. The default pane shell
        # (nu) does not load the home-manager session variables, so start the
        # server from an interactive login zsh, as a terminal does.
        ExecStart = "${config.programs.zsh.package}/bin/zsh -lic 'exec ${lib.getExe' cfg.package "herdr"} server'";
        # Send SIGTERM only to herdr, so it saves the session before it closes
        # the panes. systemd kills the remaining processes after herdr exits.
        KillMode = "mixed";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "default.target" ];
    };

    home.packages = [ cfg.package ] ++ optional cfg.gui.enable cfg.gui.package;

    home.file = mkIf (cfg.settings != { }) {
      ".config/herdr/config.toml" = {
        source = (pkgs.formats.toml { }).generate "herdr-config.toml" cfg.settings;
        mutable = true;
      };
    };

    # Regenerate the agent skill file on every home-manager switch.
    # This keeps the skill file version-matched to the installed herdr binary.
    home.activation.herdr-skill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${writeSkill}
    '';
  };
}
