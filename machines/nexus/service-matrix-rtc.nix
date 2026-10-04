# MatrixRTC for Element Call on the Tuwunel homeserver: a LiveKit SFU and
# lk-jwt-service, which gives Matrix users a LiveKit token for a call.
#
# Signaling goes through Traefik (livekit.surma.technology and
# matrix-rtc.surma.technology). Media uses UDP 50100-50200 and TCP 7881.
# Pylon forwards these ports over Tailscale to Nexus, so LiveKit
# advertises Pylon's public address.
{ config, ... }:
let
  ports = import ./ports.nix;
  ips = import ../../ips.nix;
  keyFile = "/var/lib/livekit-secrets/keys";
in
{
  # One LiveKit key for lk-jwt-service, in the form `<name>: <secret>`.
  secrets.items.livekit-keys = {
    target = keyFile;
    mode = "0400";
  };

  services.livekit = {
    enable = true;
    inherit keyFile;
    settings = {
      port = ports.livekit;
      rtc = {
        tcp_port = ports.livekitRtcTcp;
        port_range_start = ports.livekitRtcUdpStart;
        port_range_end = ports.livekitRtcUdpEnd;
        use_external_ip = false;
        node_ip = ips.hosts.pylon.ip;
      };
    };
  };
  systemd.services.livekit = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.lk-jwt-service = {
    enable = true;
    livekitUrl = "wss://livekit.surma.technology";
    inherit keyFile;
    port = ports.lkJwtService;
  };
  systemd.services.lk-jwt-service = {
    wants = [ "secrets.service" ];
    after = [ "secrets.service" ];
    # Only users of this homeserver can create calls.
    environment.LIVEKIT_FULL_ACCESS_HOMESERVERS = "matrix.surma.technology";
  };

  # The media ports arrive from Pylon over Tailscale.
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ ports.livekitRtcTcp ];
    allowedUDPPortRanges = [
      {
        from = ports.livekitRtcUdpStart;
        to = ports.livekitRtcUdpEnd;
      }
    ];
  };

  # Clients authenticate with LiveKit tokens and Matrix OpenID tokens, so
  # the public routes cannot sit behind surm-auth.
  services.surmhosting.services.matrix-rtc = {
    backend.host = "localhost";
    expose.apps.livekit = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ "livekit.surma.technology" ];
      ports = [
        {
          port = ports.livekit;
          hostname = "livekit";
        }
      ];
    };
    expose.apps.matrix-rtc = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.aliases = [ "matrix-rtc.surma.technology" ];
      ports = [
        {
          port = ports.lkJwtService;
          hostname = "matrix-rtc";
        }
      ];
    };
  };
}
