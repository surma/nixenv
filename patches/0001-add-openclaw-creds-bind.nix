# Patch: mount LLM proxy token into OpenClaw container on Nexus

# This module declares a bind mount that makes the LLM proxy token available
# inside the OpenClaw container on the Nexus host. It follows the same pattern
# used for other container token mounts in this repo.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.openclaw ?? {};
in
{
  options = {
    services.openclaw = lib.mkOption {
      type = lib.types.submodule;
      description = "OpenClaw container configuration (token bind mount).";
    };
  };

  config = lib.mkIf true {
    # Ensure the host path with the LLM proxy token exists and is mode-restricted.
    systemd.tmpfiles.rules = lib.mkDefault [
      # Create directory for nexus-mounted tokens with strict perms if missing
      "d /var/lib/openclaw/creds 0750 root root -"
    ];

    # Declare a systemd unit to mount the token into the container runtime's
    # bind-mount directory. This pattern mirrors other token mounts used for
    # github/gitlab tokens in this repo.
    systemd.units."openclaw-llm-proxy-token.mount" = {
      description = "Bind-mount LLM proxy token into OpenClaw container";
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        DefaultDependencies = "no";
      };
      serviceConfig = {};
      install.wantedBy = [ "local-fs.target" ];
      path = [ "/var/lib/openclaw/creds/llm-proxy-token" ];
      content = ''
[Unit]
Description=Bind LLM proxy token into OpenClaw container
Before=containerd.service

[Mount]
What=/etc/nexus/secrets/llm-proxy-token
Where=/var/lib/openclaw/creds/llm-proxy-token
Type=none
Options=bind,ro

[Install]
WantedBy=multi-user.target
'';
    };

    # Make sure the directory exists inside the Nexus host and is owned by root.
    environment.etc."openclaw-llm-proxy-token" = {
      source = "/var/lib/openclaw/creds/llm-proxy-token";
      mode = "0440";
      user = "root";
      group = "root";
    };
  };
}
