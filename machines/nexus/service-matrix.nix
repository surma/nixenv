{ ... }:
let
  # The server name is permanent. It becomes the suffix of every user and
  # room ID (for example `@surma:matrix.surma.technology`).
  domain = "matrix.surma.technology";
  port = 6167;
  stateDirectory = "/dump/state/tuwunel";
  secretDirectory = "/var/lib/tuwunel-secrets";
  registrationTokenFile = "${secretDirectory}/registration-token";
in
{
  # The token stays root-only on the host. The container passes it to the
  # DynamicUser service as a systemd credential.
  secrets.items.matrix-registration-token = {
    target = registrationTokenFile;
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d- ${stateDirectory} 0700 root root - -"
  ];

  # This key sorts after zz-nextcloud, which preserves every existing
  # Surmhosting container and Podman address.
  services.surmhosting.services."zz-tuwunel" = {
    backend."nixos-container" = {
      name = "lc-matrix";

      service = {
        wants = [ "secrets.service" ];
        after = [ "secrets.service" ];
      };

      bindMounts = {
        # The upstream module uses DynamicUser, so its StateDirectory lives
        # under /var/lib/private (the same pattern as Prowlarr).
        state = {
          mountPoint = "/var/lib/private/tuwunel";
          hostPath = stateDirectory;
          isReadOnly = false;
        };
        secrets = {
          mountPoint = secretDirectory;
          hostPath = secretDirectory;
          isReadOnly = true;
        };
      };

      config = {
        system.stateVersion = "26.05";

        services.matrix-tuwunel = {
          enable = true;
          settings.global = {
            server_name = domain;
            address = [ "0.0.0.0" ];
            port = [ port ];
            # A private server for Surma and Scout. No other server can
            # reach its rooms or users.
            allow_federation = false;
            trusted_servers = [ ];
            # Registration requires the token. The first registered user
            # becomes the server admin.
            allow_registration = true;
            registration_token_file = "/run/credentials/tuwunel.service/registration-token";
            new_user_displayname_suffix = "";
            well_known.client = "https://${domain}";
          };
        };

        systemd.services.tuwunel.serviceConfig.LoadCredential = [
          "registration-token:${registrationTokenFile}"
        ];
      };
    };

    # Matrix clients authenticate with Matrix access tokens, so the public
    # route cannot sit behind surm-auth.
    expose.apps.matrix = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ domain ];
      ports = [
        {
          inherit port;
          hostname = "matrix";
        }
      ];
    };
  };
}
