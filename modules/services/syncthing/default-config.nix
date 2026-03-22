{
  config,
  lib,
  ...
}:
let
  mkOptionalAttr = v: obj: if v then obj else { };

  inherit (config.defaultConfigs) syncthing;
in
with lib;
{
  options = {
    defaultConfigs.syncthing = {
      enable = mkEnableOption "";
      knownFolders.scratch.enable = mkEnableOption "";
      knownFolders.audiobooks.enable = mkEnableOption "";
      knownFolders.ebooks.enable = mkEnableOption "";
      knownFolders.surmvault.enable = mkEnableOption "";
    };
  };
  config = mkIf (syncthing.enable) {
    services.syncthing = {
      settings = {
        devices = {
          nexus = {
            id = "CJT6SJ3-YD5KOXR-WRLN3GM-D5ALFHQ-7M6ZWSG-4MNKWG3-T525QU4-M77GYA3";
            addresses = [
              "tcp://10.0.0.2:22000"
              "tcp://sync.surmcluster.surmnet.surma.link:22000"
            ];
          };
        };
        folders =
          (mkOptionalAttr syncthing.knownFolders.scratch.enable {
            "${config.home.homeDirectory}/sync/scratch" = {
              id = "scratch";
              devices = [ "nexus" ];
            };
          })
          // (mkOptionalAttr syncthing.knownFolders.audiobooks.enable {
            "${config.home.homeDirectory}/sync/audiobooks" = {
              id = "audiobooks";
              devices = [ "nexus" ];
            };
          })
          // (mkOptionalAttr syncthing.knownFolders.ebooks.enable {
            "${config.home.homeDirectory}/sync/ebooks" = {
              id = "ebooks";
              devices = [ "nexus" ];
            };
          })
          // (mkOptionalAttr syncthing.knownFolders.surmvault.enable {
            "${config.home.homeDirectory}/sync/surmvault" = {
              id = "surmvault";
              devices = [ "nexus" ];
            };
          });
      };
    };
  };
}
