{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /dump/state/hedgedoc 0755 root root - -"
  ];

  services.surmhosting.services.hedgedoc.expose.port = 3000;
  services.surmhosting.services.hedgedoc.container = {
    config = {
      system.stateVersion = "25.05";

      services.hedgedoc = {
        enable = true;
        settings = {
          # Listen on the container veth so the host Traefik can reach it
          # (the module default of "localhost" is loopback-only).
          host = "0.0.0.0";
          port = 3000;

          domain = "hedgedoc.surma.technology";
          protocolUseSSL = true;

          # Access is gated at the edge by surm-auth (GitHub allowlist on
          # pylon), so inside the perimeter HedgeDoc runs fully anonymous —
          # no HedgeDoc accounts, no login UI, shared workspace.
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
  };
}
