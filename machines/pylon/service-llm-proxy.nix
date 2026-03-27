{ pkgs, inputs, ... }:
{
  secrets.items.llm-proxy-secret = {
    target = "/var/lib/llm-proxy-credentials/receiver-secret";
    mode = "0644";
  };
  secrets.items.llm-proxy-client-key = {
    target = "/var/lib/llm-proxy-credentials/client-key";
    mode = "0644";
  };
  secrets.items.openrouter-api-key = {
    target = "/var/lib/llm-proxy-credentials/openrouter-key";
    mode = "0644";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llm-proxy 0755 root root -"
    "d /var/lib/llm-proxy-credentials 0755 root root -"
  ];

  services.surmhosting.services.llm-proxy = {
    expose.ports = [
      {
        port = 4000;
        hostname = "proxy-llm";
        rule = "Host(`proxy.llm.surma.technology`)";
      }
      {
        port = 8080;
        hostname = "key-llm";
        rule = "Host(`key.llm.surma.technology`)";
      }
      {
        port = 4001;
        hostname = "vendors-llm";
        rule = "Host(`vendors.llm.surma.technology`)";
      }
    ];
    container = {
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
  };
}
