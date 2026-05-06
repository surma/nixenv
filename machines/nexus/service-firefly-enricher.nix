{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  gwsPkg = inputs.gws.packages.${system}.default;

  enricher = pkgs.writers.writePython3Bin "firefly-enricher" {
    libraries = with pkgs.python3Packages; [
      requests
      pyyaml
    ];
    flakeIgnore = [
      "E501" # line length
      "E203" # whitespace before colon
      "W503" # line break before binary op
    ];
  } (builtins.readFile ./firefly-enricher/enricher.py);

  # Reads credentials from the host paths populated by the existing
  # `scout-gws-credentials` and `firefly-access-token` secrets. Both are
  # 0644 root-owned on disk, so a DynamicUser service can read them.
  runEnricher = pkgs.writeShellScript "firefly-run-enricher.sh" ''
    set -euo pipefail
    export PATH=${gwsPkg}/bin:${pkgs.coreutils}/bin:$PATH
    export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/var/lib/scout/gws-credentials.json
    export FIREFLY_TOKEN_FILE=/var/lib/firefly-importer/access-token.txt
    export FIREFLY_URL="http://firefly.nexus.hosts.10.0.0.2.nip.io"
    exec ${enricher}/bin/firefly-enricher "$@"
  '';
in
{
  systemd.services.firefly-enricher = {
    description = "Firefly III enricher (resolves opaque merchants from Gmail receipts)";
    after = [
      "network-online.target"
      "secrets.service"
    ];
    wants = [
      "network-online.target"
      "secrets.service"
    ];
    unitConfig.OnSuccess = "firefly-categoriser.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runEnricher;
      DynamicUser = true;
      TimeoutStartSec = "1800";
    };
  };

  systemd.paths.firefly-pipeline = {
    description = "Trigger Firefly enrichment pipeline after successful import";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/var/lib/firefly-importer-stamps/last-import-success";
      Unit = "firefly-enricher.service";
    };
  };
}
