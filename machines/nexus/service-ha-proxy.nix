# Home Assistant proxy on Nexus (moved from Pylon's service-ha-proxy.nix).
#
# Home Assistant keeps its own application login; the logical app is
# `public`, so no surm-auth middleware is applied. The backend is the
# Tailscale address of the Home Assistant instance from the IP registry.
let
  ips = import ../../ips.nix;
in
{
  services.surmhosting.services.ha = {
    backend.host = ips.hosts.homeassistant.tailscale;

    expose.apps.ha = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ "ha.surma.technology" ];
      ports = [
        {
          port = 8123;
          hostname = "ha";
        }
      ];
    };
  };
}
