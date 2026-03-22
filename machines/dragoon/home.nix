{ config, pkgs, lib, ... }:
{
  imports = [
    # Programs now globally injected
    # ../../modules/programs/telegram

    # Application modules now globally injected
    # Application modules now globally injected
    # ../../modules/home-manager/claude-code
    # ../../modules/home-manager/opencode
    # ../../modules/home-manager/ghostty
    # ../../modules/home-manager/handy
    # ../../modules/services/syncthing

    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/workstation.nix
    ../../profiles/home-manager/graphical.nix
    ../../profiles/home-manager/physical.nix
    ../../profiles/home-manager/macos.nix
    ../../profiles/home-manager/experiments.nix
    ../../profiles/home-manager/cloud.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/javascript.nix
    ../../profiles/home-manager/godot.nix
  ];

  home.stateVersion = "24.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#surmbook";

  allowedUnfreeApps = [
    "claude-code"
    "obsidian"
  ];

  home.packages = (
    with pkgs;
    [
      openscad
      jqp
      ollama
      qbittorrent
      jupyter
      gopls
      bun
    ]
  );

  programs.telegram.enable = true;
  programs.claude-code.enable = true;
  defaultConfigs.claude-code.enable = true;
  programs.opencode.enable = true;
  defaultConfigs.opencode.enable = true;
  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;
  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  defaultConfigs.helix.enableSlSyntax = true;
  programs.ghostty.enable = true;
  defaultConfigs.ghostty.enable = true;
  programs.handy.enable = true;
  defaultConfigs.handy.enable = true;
  programs.obsidian.enable = true;

  programs.go.enable = true;

  customScripts.denix.enable = true;
  customScripts.noti.enable = true;
  customScripts.llm-proxy.enable = true;
  customScripts.ghclone.enable = true;
  customScripts.ccp.enable = true;
  customScripts.wallpaper-shuffle.enable = true;
  customScripts.wallpaper-shuffle.asDesktopItem = true;
  customScripts.oc.enable = true;
  customScripts.ocq.enable = true;

  xdg.configFile = {
    "dump/config.json".text = builtins.toJSON { server = "http://10.0.0.2:8081"; };
  };

  secrets.items.syncthing-relay-token.target = "${config.home.homeDirectory}/.local/state/syncthing-relay/token";

  home.activation.syncthingPrivateRelay = lib.hm.dag.entryAfter [
    "writeBoundary"
    "secrets"
  ] ''
    set -euo pipefail

    token_file="${config.secrets.items.syncthing-relay-token.target}"
    config_xml="$HOME/Library/Application Support/Syncthing/config.xml"
    relay_prefix="relay://relay.sync.surma.technology:22067/"

    if [ -s "$token_file" ] && [ -f "$config_xml" ]; then
      api_key="$(${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' "$config_xml" 2>/dev/null || true)"
      if [ -n "$api_key" ]; then
        relay_token="$(${pkgs.coreutils}/bin/tr -d '\n' < "$token_file")"
        relay_url="$relay_prefix?token=$relay_token"

        current_options="$(${pkgs.curl}/bin/curl -fsSk -H "X-API-Key: $api_key" http://127.0.0.1:8384/rest/config/options 2>/dev/null || true)"
        if [ -n "$current_options" ]; then
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
            | ${pkgs.curl}/bin/curl -fsSk -H "X-API-Key: $api_key" -X PUT -d @- http://127.0.0.1:8384/rest/config/options >/dev/null

          restart_required="$(${pkgs.curl}/bin/curl -fsSk -H "X-API-Key: $api_key" http://127.0.0.1:8384/rest/config/restart-required | ${pkgs.jq}/bin/jq -r '.requiresRestart')"
          if [ "$restart_required" = "true" ]; then
            ${pkgs.curl}/bin/curl -fsSk -H "X-API-Key: $api_key" -X POST http://127.0.0.1:8384/rest/system/restart >/dev/null
          fi
        fi
      fi
    fi
  '';

  services.syncthing.enable = true;
  services.syncthing.settings.folders."${config.home.homeDirectory}/SurmVault" = {
    id = "surmvault";
    devices = [ "nexus" ];
  };
  defaultConfigs.syncthing.enable = true;
  defaultConfigs.syncthing.knownFolders.scratch.enable = true;
  defaultConfigs.syncthing.knownFolders.ebooks.enable = true;

}
