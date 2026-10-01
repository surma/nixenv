# Binary cache for the x86_64 machines in this repo.
#
# Harmonia serves the Nexus Nix store and signs every path on the fly. The
# nixenv CI workflow (.github/workflows/ci.yml) builds all x86_64 machines on
# the GitHub runner container, which shares this store, and pins the latest
# builds as GC roots. Clients use profiles/nixos/nexus-cache.nix.
#
# The cache is internal only: the trusted-network policy limits it to the LAN
# and the tailnet, and there is no public router.
{ ... }:
let
  ports = import ./ports.nix;
  signingKeyPath = "/var/lib/nix-cache/signing-key";
in
{
  secrets.items.nexus-cache-signing-key = {
    target = signingKeyPath;
    mode = "0400";
  };

  services.harmonia.cache = {
    enable = true;
    # A string, not a Nix path: the key must never enter the store.
    signKeyPaths = [ signingKeyPath ];
    # Traefik is the only client. The module default (priority 50) keeps
    # cache.nixos.org (priority 40) first for everything it has.
    settings.bind = "127.0.0.1:${toString ports.nixCache}";
  };

  systemd.services.harmonia = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.nix-cache = {
    backend.host = "localhost";
    expose.apps.nix-cache = {
      # Nix clients cannot log in. The internal router only accepts the
      # trusted network, and public.enable = false emits no public route.
      access.mode = "public";
      internal.access = "trusted-network";
      public.enable = false;
      ports = [
        {
          port = ports.nixCache;
          hostname = "cache";
        }
      ];
    };
  };
}
