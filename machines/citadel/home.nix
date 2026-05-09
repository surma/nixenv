{
  config,
  lib,
  pkgs,
  ...
}:
let
  zellijWebPort = 88123;
  zellijWebTokenHash = "10534faf201c258c3644386a7957bee71694e7b420aaefa37707b0e8041d36f9";
  zellijWebTokenName = "surma";
  zellijWebTokenDb = "${config.xdg.dataHome}/zellij/tokens.db";
  zellij = "${config.programs.zellij.package}/bin/zellij";
  ensureZellijWebToken = pkgs.writeShellScript "ensure-zellij-web-token" ''
    set -eu

    db=${lib.escapeShellArg zellijWebTokenDb}
    sqlite=${pkgs.sqlite}/bin/sqlite3
    zellij=${lib.escapeShellArg zellij}

    # Let Zellij create and migrate its own token database. This creates a
    # throwaway random token, which we immediately revoke before inserting the
    # declarative token below.
    created_token="$($zellij web --create-token)"
    created_token_name=
    while IFS= read -r line; do
      case "$line" in
        *:*)
          created_token_name=''${line%%:*}
          break
          ;;
      esac
    done <<EOF
    $created_token
    EOF

    if [ -z "$created_token_name" ]; then
      echo "Could not parse temporary Zellij token name" >&2
      exit 1
    fi

    $zellij web --revoke-token "$created_token_name" >/dev/null

    "$sqlite" "$db" <<'SQL'
    DELETE FROM tokens
      WHERE (name = '${zellijWebTokenName}' AND token_hash != '${zellijWebTokenHash}')
        OR (token_hash = '${zellijWebTokenHash}' AND name != '${zellijWebTokenName}');
    INSERT OR IGNORE INTO tokens (token_hash, name)
      VALUES ('${zellijWebTokenHash}', '${zellijWebTokenName}');
    SQL
  '';
in
{
  imports = [
    ../../scripts

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/ai.nix
  ];

  config = {
    allowedUnfreeApps = [
      "claude-code"
    ];

    secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

    home.stateVersion = "25.05";

    defaultConfigs.agents.enable = true;
    customScripts.llm-proxy.enable = true;
    customScripts.flacsplit.enable = true;
    customScripts.oc.enable = true;
    customScripts.ocq.enable = true;

    home.packages = (
      with pkgs;
      [
        gopls
        gcc
      ]
    );
    programs.go.enable = true;

    programs.pi.enable = true;
    defaultConfigs.pi.enable = true;
    defaultConfigs.pi.extensions.proxy.enable = true;

    systemd.user.services.zellij-web = {
      Unit = {
        Description = "Zellij web server";
        After = [ "network.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${ensureZellijWebToken}";
        ExecStart = "${config.programs.zellij.package}/bin/zellij web --start --ip 127.0.0.1 --port ${toString zellijWebPort}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    defaultConfigs.helix.enableSlSyntax = true;
    programs.opencode.enable = true;
    defaultConfigs.opencode.enable = true;
  };
}
