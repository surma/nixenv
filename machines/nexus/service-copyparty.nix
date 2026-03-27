{ pkgs, inputs, ... }:
{
  secrets.items.nexus-copyparty.command = ''
    cat > /var/lib/copyparty/surma.passwd
    chmod 0644 /var/lib/copyparty/surma.passwd
  '';

  services.surmhosting.services.copyparty.expose.port = 8080;
  services.surmhosting.services.copyparty.container = {
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
          services.copyparty.package = inputs.copyparty.packages.${pkgs.stdenv.system}.copyparty;
          services.copyparty = {
            accounts.surma.passwordFile = "/var/lib/credentials/copyparty/surma.passwd";
            settings.p = [ 8080 ];
            volumes."/all" = {
              path = "/dump";
              access.A = [ "surma" ];
            };
            volumes."/tv" = {
              path = "/dump/TV";
              access.r = "*";
            };
            volumes."/movies" = {
              path = "/dump/Tovies";
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
