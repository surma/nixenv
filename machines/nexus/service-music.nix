{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Wrapper around ffmpeg that injects `-ac 2` (stereo output) when encoding
  # to Opus. libopus caps mono bitrate at 256 kbps, so Navidrome's default
  # 320 kbps request fails with empty output for mono source files.  Forcing
  # stereo raises the ceiling to 510 kbps and is a no-op for already-stereo
  # input.
  ffmpeg-wrapper = pkgs.writeShellScript "ffmpeg-opus-wrapper" ''
    is_opus=false
    for a in "$@"; do
      [ "$a" = "libopus" ] && is_opus=true
    done
    if "$is_opus"; then
      new=()
      for a in "$@"; do
        if [ "$a" = "-c:a" ]; then
          new+=("-ac" "2" "-c:a")
        else
          new+=("$a")
        fi
      done
      exec ${pkgs.ffmpeg}/bin/ffmpeg "''${new[@]}"
    else
      exec ${pkgs.ffmpeg}/bin/ffmpeg "$@"
    fi
  '';
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
        Scanner.Schedule = "@every 5m";
        FFmpegPath = "${ffmpeg-wrapper}";
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
