{ pkgs, inputs, ... }:
{
  secrets.items.nexus-copyparty.command = ''
    cat > /var/lib/copyparty/surma.passwd
    chmod 0644 /var/lib/copyparty/surma.passwd
  '';

  services.surmhosting.services.copyparty.expose.apps.copyparty = {
    access.mode = "allowlist";
    access.seedUsers = [ "surma" ];
    internal.access = "trusted-network";
    ports = [
      {
        port = 8080;
        hostname = "copyparty";
      }
    ];
  };
  services.surmhosting.services.copyparty.backend."nixos-container" = {
    config =
      { ... }:
      {
        imports = [
          inputs.copyparty.nixosModules.default
        ];
        config = {
          system.stateVersion = "25.05";
          services.copyparty.enable = true;
          services.copyparty.user = "containeruser";
          services.copyparty.package = inputs.copyparty.packages.${pkgs.stdenv.hostPlatform.system}.copyparty;
          services.copyparty = {
            accounts.surma.passwordFile = "/var/lib/credentials/copyparty/surma.passwd";
            settings.p = [ 8080 ];
            # Trust X-Forwarded-* from the surmhosting proxy. Without this,
            # copyparty assumes http:// and rejects logins in the CORS check.
            settings.xff-src = "10.201.0.0/16";
            settings.rproxy = -1;
            volumes."/all" = {
              path = "/dump";
              access.A = [ "surma" ];
            };
            volumes."/tv" = {
              path = "/dump/TV";
              access.r = "*";
            };
            volumes."/movies" = {
              path = "/dump/Movies";
              access.r = "*";
            };
            volumes."/music" = {
              path = "/dump/music";
              access.r = "*";
            };
          };
        };
      };

    bindMounts.dump = {
      mountPoint = "/dump";
      hostPath = "/dump";
      isReadOnly = false;
    };
    bindMounts.creds = {
      mountPoint = "/var/lib/credentials/copyparty";
      hostPath = "/var/lib/copyparty";
      isReadOnly = true;
    };
  };
}
