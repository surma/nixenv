{
  lib,
  config,
  pkgs,
  systemManager,
  ...
}:
let
  cfg = config.programs.gitea-cli;
in
{
  options.programs.gitea-cli = {
    enable = lib.mkEnableOption "Gitea CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.tea;
      description = "The Gitea CLI package to install.";
    };

    loginName = lib.mkOption {
      type = lib.types.str;
      default = "gitea";
      description = "Name of the tea login entry.";
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://gitea.nexus.hosts.10.0.0.2.nip.io";
      description = "Gitea server URL used by tea.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "surma";
      description = "Gitea user associated with the configured token.";
    };
  };

  config = lib.mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];

    secrets.items.gitea-cli-pat.command = ''
      token="$(cat)"
      config_dir="$HOME/.config/tea"
      config_file="$config_dir/config.yml"

      mkdir -p "$config_dir"
      umask 077
      cat > "$config_file" <<EOF
      logins:
          - name: ${cfg.loginName}
            url: ${cfg.serverUrl}
            token: $token
            default: true
            ssh_host: gitea.nexus.hosts.10.0.0.2.nip.io
            ssh_key: $HOME/.ssh/id_machine
            insecure: false
            ssh_certificate_principal: ""
            ssh_agent: false
            ssh_key_agent_pub: ""
            version_check: false
            user: ${cfg.user}
            created: 0
            refresh_token: ""
            token_expiry: 0
      preferences:
          editor: false
          flag_defaults:
              remote: ""
      EOF
      chmod 600 "$config_file"
    '';
  };
}
