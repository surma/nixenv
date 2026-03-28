{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkOptionalAttr = v: obj: if v then obj else { };
  mkKnownFolderOption = {
    enable = lib.mkEnableOption "";
    path = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
  };

  folderPath = configuredPath: defaultPath: if configuredPath != null then configuredPath else defaultPath;

  shared = import ./common.nix { inherit lib pkgs; };
  inherit (config.defaultConfigs) syncthing;
in
with lib;
{
  options = {
    defaultConfigs.syncthing = {
      enable = mkEnableOption "";

      privateRelay = {
        enable = mkEnableOption "";
        tokenFile = mkOption {
          type = with types; nullOr str;
          default = null;
        };
      };

      knownFolders = {
        scratch = mkKnownFolderOption;
        audiobooks = mkKnownFolderOption;
        ebooks = mkKnownFolderOption;
        surmvault = mkKnownFolderOption;
      };
    };
  };

  config = mkMerge [
    (mkIf syncthing.enable {
      services.syncthing = {
        settings = {
          devices.nexus = shared.devices.nexus;
          folders =
            (mkOptionalAttr syncthing.knownFolders.scratch.enable {
              "${folderPath syncthing.knownFolders.scratch.path "${config.home.homeDirectory}/sync/scratch"}" = {
                id = "scratch";
                devices = [ "nexus" ];
              };
            })
            // (mkOptionalAttr syncthing.knownFolders.audiobooks.enable {
              "${folderPath syncthing.knownFolders.audiobooks.path "${config.home.homeDirectory}/sync/audiobooks"}" = {
                id = "audiobooks";
                devices = [ "nexus" ];
              };
            })
            // (mkOptionalAttr syncthing.knownFolders.ebooks.enable {
              "${folderPath syncthing.knownFolders.ebooks.path "${config.home.homeDirectory}/sync/ebooks"}" = {
                id = "ebooks";
                devices = [ "nexus" ];
              };
            })
            // (mkOptionalAttr syncthing.knownFolders.surmvault.enable {
              "${folderPath syncthing.knownFolders.surmvault.path "${config.home.homeDirectory}/sync/surmvault"}" = {
                id = "surmvault";
                devices = [ "nexus" ];
              };
            });
        };
      };
    })

    (mkIf (syncthing.enable && syncthing.privateRelay.enable) {
      assertions = [
        {
          assertion = syncthing.privateRelay.tokenFile != null;
          message = "defaultConfigs.syncthing.privateRelay.tokenFile must be set when the private relay is enabled.";
        }
      ];

      home.activation.syncthingPrivateRelay = lib.hm.dag.entryAfter [
        "writeBoundary"
        "secrets"
      ] ''
        ${shared.mkPrivateRelayScript {
          tokenFile = syncthing.privateRelay.tokenFile;
          configXml = "${config.home.homeDirectory}/Library/Application Support/Syncthing/config.xml";
          apiUrl = "http://127.0.0.1:8384";
          allowMissing = true;
        }}
      '';
    })
  ];
}
