{ lib, pkgs }:
let
  relayPrefix = "relay://relay.sync.surma.technology:22067/";

  devices = {
    nexus = {
      id = "EWY3UBE-CTNAGZQ-NTXKOP4-5XJQSE4-LB75KC4-SBRDB6D-5F3WHHM-CC5NYQB";
      addresses = [
        "dynamic"
        "tcp://10.0.0.2:22000"
      ];
    };

    dragoon = {
      id = "TAYU7SA-CCAFI4R-ZLB6FNM-OCPMW5W-6KEYYPI-ANW52FK-DUHVT7Z-L2GYBAB";
      addresses = [ "dynamic" ];
    };

    archon = {
      id = "QMJUC42-YAD6POQ-VPB6MXP-ISYC6JK-3V7FIWH-VKNQACU-VWXYM5A-NXX6RQ6";
      addresses = [ "dynamic" ];
    };

    # Android device; update the ID here manually if the app/device identity changes.
    arbiter = {
      id = "7HXMC4G-66H3UDT-BRJ6ATT-3HOXUVN-XIMDBOT-JSFEOO3-HRR3NVF-P4GFUQN";
      addresses = [ "dynamic" ];
    };

    shopisurm = {
      id = "DIQ23PM-ULHTRJC-EJVWAAI-NPBLTKZ-6DXSYB5-NYQP3DN-SKFJUVX-JML3PAA";
      addresses = [ "dynamic" ];
    };
  };

  mkPrivateRelayScript =
    {
      tokenFile,
      configXml,
      apiUrl,
      curlExtraArgs ? "",
      allowMissing ? false,
    }:
    pkgs.writeShellScript "syncthing-private-relay" ''
      set -euo pipefail

      token_file=${lib.escapeShellArg tokenFile}
      config_xml=${lib.escapeShellArg configXml}
      relay_prefix=${lib.escapeShellArg relayPrefix}
      api_url=${lib.escapeShellArg apiUrl}

      ${lib.optionalString allowMissing ''
        if ! [ -s "$token_file" ] || ! [ -f "$config_xml" ]; then
          exit 0
        fi
      ''}
      ${lib.optionalString (!allowMissing) ''
        [ -s "$token_file" ]
        [ -f "$config_xml" ]
      ''}

      api_key="$(${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' "$config_xml" 2>/dev/null || true)"
      ${lib.optionalString allowMissing ''
        if [ -z "$api_key" ]; then
          exit 0
        fi
      ''}
      ${lib.optionalString (!allowMissing) ''
        [ -n "$api_key" ]
      ''}

      relay_token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"
      relay_url="$relay_prefix?token=$relay_token"

      api_curl() {
        ${pkgs.curl}/bin/curl -fsSk ${curlExtraArgs} -H "X-API-Key: $api_key" "$@"
      }

      current_options="$(api_curl "$api_url/rest/config/options" 2>/dev/null || true)"
      if [ -z "$current_options" ]; then
        ${if allowMissing then "exit 0" else "exit 1"}
      fi

      updated_options="$(
        printf '%s' "$current_options" | ${pkgs.jq}/bin/jq --arg relay "$relay_url" --arg prefix "$relay_prefix" '
          .listenAddresses = (
            [ $relay ]
            + ((.listenAddresses // []) | map(select(startswith($prefix) | not)))
            | unique
          )
        '
      )"

      printf '%s' "$updated_options" \
        | api_curl -X PUT -d @- "$api_url/rest/config/options" >/dev/null

      restart_required="$(api_curl "$api_url/rest/config/restart-required" | ${pkgs.jq}/bin/jq -r '.requiresRestart')"
      if [ "$restart_required" = "true" ]; then
        api_curl -X POST "$api_url/rest/system/restart" >/dev/null
      fi
    '';
in
{
  inherit devices relayPrefix mkPrivateRelayScript;
}
