# Home Assistant proxy on Nexus (moved from Pylon's service-ha-proxy.nix).
#
# Home Assistant keeps its own application login; the logical app is
# `public`, so no surm-auth middleware is applied. The backend is the
# existing Tailscale address of the Home Assistant instance, unchanged.
{
  services.surmhosting.services.ha = {
    host = "100.97.65.42";

    expose.apps.ha = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.domain = "ha.apps.surma.technology";
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
