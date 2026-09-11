# LLM proxy on Nexus (moved from Pylon; auth-rework sections 4.3 and 6.5).
#
# Three public logical apps, one per listener port. Each port must map
# to exactly one app key so an alias can never reach a sibling port.
# The backends keep their own application authentication (client key,
# receiver secret, OpenRouter key); `public` only means no surm-auth
# middleware. The legacy *.llm.surma.technology aliases follow the
# service move and stay on the same policy as their primary domain.
#
# Secret consumer paths are resolved by the host-level secrets commands:
# - llm-proxy-secret (default.nix) writes receiver-secret here and the
#   poller's root-only copy.
# - llm-proxy-client-key and openrouter-api-key (service-scout.nix)
#   write the Scout copies plus the files in the credential directory.
{
  systemd.tmpfiles.rules = [
    "d /var/lib/llm-proxy 0755 root root -"
    "d /var/lib/llm-proxy-credentials 0755 root root -"
  ];

  # The secret commands also enforce this directory mode on an already
  # running host. The ordering prevents a first boot race with tmpfiles.
  systemd.services.secrets = {
    after = [ "systemd-tmpfiles-setup.service" ];
    requires = [ "systemd-tmpfiles-setup.service" ];
  };

  services.surmhosting.services.llm-proxy.containerService = {
    wants = [ "secrets.service" ];
    # Top-level (unit section) Requires=: a failed or missing secrets.service
    # must prevent the LLM container from starting, not only order it later.
    requires = [ "secrets.service" ];
    after = [ "secrets.service" ];
  };

  services.surmhosting.services.llm-proxy.expose.apps = {
    proxy-llm = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.domain = "proxy-llm.apps.surma.technology";
      public.aliases = [ "proxy.llm.surma.technology" ];
      ports = [
        {
          port = 4000;
          hostname = "proxy-llm";
        }
      ];
    };

    key-llm = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.domain = "key-llm.apps.surma.technology";
      public.aliases = [ "key.llm.surma.technology" ];
      ports = [
        {
          port = 8080;
          hostname = "key-llm";
        }
      ];
    };

    vendors-llm = {
      access.mode = "public";
      internal.access = "trusted-network";
      public.domain = "vendors-llm.apps.surma.technology";
      public.aliases = [ "vendors.llm.surma.technology" ];
      ports = [
        {
          port = 4001;
          hostname = "vendors-llm";
        }
      ];
    };
  };

  services.surmhosting.services.llm-proxy.container = {
    config =
      { pkgs, ... }:
      {
        imports = [ ../../modules/services/llm-proxy ];

        system.stateVersion = "25.05";

        services.llm-proxy.enable = true;
        services.llm-proxy.keyReceiver.enable = true;
        services.llm-proxy.keyReceiver.secretFile = "/var/lib/credentials/receiver-secret";
        services.llm-proxy.providers.shopify.enable = true;
        services.llm-proxy.providers.openrouter.enable = true;
        services.llm-proxy.providers.openrouter.keyFile = "/var/lib/credentials/openrouter-key";
        services.llm-proxy.providers.openrouter.models = [
          "qwen/qwen3-235b-a22b-2507"
          "anthropic/claude-opus-4.5"
          "anthropic/claude-sonnet-4.5"
          "openai/gpt-5.1-codex-max"
        ];
        services.llm-proxy.clientAuth.enable = true;
        services.llm-proxy.clientAuth.keyFile = "/var/lib/credentials/client-key";
        services.llm-proxy.disableAllUI = true;
        services.llm-proxy.vendorProxy.enable = true;
      };

    bindMounts = {
      # Mutable LLM state is copied from Pylon's /var/lib/llm-proxy during
      # the maintenance window (operator step; not part of this change).
      state = {
        mountPoint = "/var/lib/llm-proxy";
        hostPath = "/var/lib/llm-proxy";
        isReadOnly = false;
      };
      credentials = {
        mountPoint = "/var/lib/credentials";
        hostPath = "/var/lib/llm-proxy-credentials";
        isReadOnly = true;
      };
    };
  };
}
