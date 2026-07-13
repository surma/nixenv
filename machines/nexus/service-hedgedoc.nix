{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /dump/state/hedgedoc 0750 999 999 - -"
  ];

  # GitHub OAuth client id/secret for HedgeDoc's own login, provisioned by the
  # host secrets service as a systemd EnvironmentFile (CMD_GITHUB_CLIENTID /
  # CMD_GITHUB_CLIENTSECRET) and bind-mounted read-only into the container.
  secrets.items.hedgedoc-github-env = {
    target = "/var/lib/hedgedoc-secrets/env";
    mode = "0444";
  };

  services.surmhosting.services.hedgedoc.containerService = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.hedgedoc.expose.port = 3000;
  services.surmhosting.services.hedgedoc.container = {
    config = {
      system.stateVersion = "25.05";

      services.hedgedoc = {
        enable = true;
        # CMD_GITHUB_CLIENTID / CMD_GITHUB_CLIENTSECRET live here; HedgeDoc
        # auto-enables GitHub login when both are set. surm-auth still gates
        # who can reach the app; GitHub login just establishes per-user
        # identity (history, note ownership) on top.
        environmentFile = "/var/lib/hedgedoc-secrets/env";
        settings = {
          # Listen on the container veth so the host Traefik can reach it
          # (the module default of "localhost" is loopback-only).
          host = "0.0.0.0";
          port = 3000;

          domain = "hedgedoc.surma.technology";
          protocolUseSSL = true;

          # Access is gated at the edge by surm-auth (GitHub allowlist on
          # pylon). Anonymous use is still allowed, but signing in with GitHub
          # (see environmentFile above) gives per-user identity: synced
          # server-side history and note ownership. Local email accounts stay
          # disabled — GitHub is the only login method.
          allowAnonymous = true;
          allowAnonymousEdits = true;
          allowFreeURL = true;
          defaultPermission = "freely";
          email = false;
          allowEmailRegister = false;
        };
      };
    };

    # Persist SQLite DB (/var/lib/hedgedoc/db.sqlite) and uploaded images
    # (/var/lib/hedgedoc/uploads) on the host.
    bindMounts.state = {
      mountPoint = "/var/lib/hedgedoc";
      hostPath = "/dump/state/hedgedoc";
      isReadOnly = false;
    };

    bindMounts.github-secret = {
      mountPoint = "/var/lib/hedgedoc-secrets";
      hostPath = "/var/lib/hedgedoc-secrets";
      isReadOnly = true;
    };
  };
}
