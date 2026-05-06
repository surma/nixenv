{ pkgs, ... }:
let
  taxonomyFile = ./firefly-categoriser/taxonomy.json;
  merchantMapFile = ./firefly-categoriser/merchant-map.json;

  categoriser = pkgs.writers.writePython3Bin "firefly-categoriser" {
    libraries = with pkgs.python3Packages; [
      requests
      pyyaml
    ];
    flakeIgnore = [
      "E501" # line length
      "E203" # whitespace before colon
      "W503" # line break before binary op
    ];
  } (builtins.readFile ./firefly-categoriser/categoriser.py);

  runCategoriser = pkgs.writeShellScript "firefly-run-categoriser.sh" ''
    set -euo pipefail
    export FIREFLY_TOKEN_FILE=/var/lib/firefly-importer/access-token.txt
    export FIREFLY_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    export LLM_ENDPOINT="https://proxy.llm.surma.technology/v1"
    export LLM_KEY_FILE=/var/lib/scout/llm-proxy-client-key
    export LLM_MODEL="shopify:anthropic:claude-haiku-4-5"
    export CATEGORISER_TAXONOMY_FILE=${taxonomyFile}
    export CATEGORISER_MAP_FILE=${merchantMapFile}
    exec ${categoriser}/bin/firefly-categoriser run "$@"
  '';
in
{
  environment.systemPackages = [ categoriser ];

  systemd.services.firefly-categoriser = {
    description = "Firefly III categoriser (categories + roll-up tags)";
    after = [
      "network-online.target"
      "secrets.service"
    ];
    wants = [
      "network-online.target"
      "secrets.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runCategoriser;
      DynamicUser = true;
      TimeoutStartSec = "1800";
    };
  };
}
