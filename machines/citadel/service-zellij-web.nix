{ pkgs, lib, ... }:
let
  ports = import ./ports.nix;
  zellijWebTokenHash = "10534faf201c258c3644386a7957bee71694e7b420aaefa37707b0e8041d36f9";
  zellijWebTokenName = "surma";
in
{
  users.users.surma.linger = true;

  services.surmhosting.services.terminal = {
    host = "localhost";
    expose.port = ports.zellijWeb;
  };

  home-manager.users.surma =
    { config, ... }:
    let
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
        INSERT INTO tokens (token_hash, name)
          VALUES ('${zellijWebTokenHash}', '${zellijWebTokenName}')
          ON CONFLICT(name) DO UPDATE SET
            token_hash = excluded.token_hash;
        SQL
      '';
    in
    {
      systemd.user.services.zellij-web = {
        Unit = {
          Description = "Zellij web server";
          After = [ "network.target" ];
        };
        Service = {
          Type = "simple";
          ExecStartPre = "${ensureZellijWebToken}";
          ExecStart = "${config.programs.zellij.package}/bin/zellij web --start --ip 127.0.0.1 --port ${toString ports.zellijWeb}";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
