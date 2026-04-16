{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  services.surmhosting.services.music.expose.port = 8080;
  services.surmhosting.services.music.container = {
    config = {
      system.stateVersion = "25.05";

      services.navidrome.enable = true;
      services.navidrome.package = pkgs-unstable.navidrome;
      services.navidrome.user = "containeruser";
      services.navidrome.settings = {
        MusicFolder = "/dump/music";
        DataFolder = "/dump/state/navidrome";
        DefaultDownloadableShare = true;
        Scanner.PurgeMissing = "full";
        Address = "0.0.0.0";
        Port = 8080;
      };

      systemd.services.navidrome.serviceConfig.MemoryDenyWriteExecute = lib.mkForce false;
    };

    bindMounts = {
      music = {
        mountPoint = "/dump/music";
        hostPath = "/dump/music";
        isReadOnly = true;
      };
      state = {
        mountPoint = "/dump/state/navidrome";
        hostPath = "/dump/state/navidrome";
        isReadOnly = false;
      };
    };
  };
}
