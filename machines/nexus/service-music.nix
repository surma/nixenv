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
  #
  # Packaged as a directory with both `ffmpeg` (wrapper) and `ffprobe`
  # (symlink) so Navidrome can find ffprobe next to the configured FFmpegPath.
  ffmpeg-opus-wrapper = pkgs.writeShellScript "ffmpeg-opus-wrapper" ''
    is_opus=false
    for a in "$@"; do
      [ "$a" = "libopus" ] && is_opus=true
    done
    if "$is_opus"; then
      # Replace any existing -ac value with 2, or add -ac 2 if absent.
      # Navidrome may inject -ac 1 (source channels) which overrides an
      # earlier -ac 2 since ffmpeg honours the last occurrence.
      new=()
      found_ac=false
      skip_next=false
      for a in "$@"; do
        if "$skip_next"; then
          new+=("2")
          skip_next=false
          found_ac=true
        elif [ "$a" = "-ac" ]; then
          new+=("-ac")
          skip_next=true
        else
          new+=("$a")
        fi
      done
      if ! "$found_ac"; then
        # Insert -ac 2 before the trailing "-" (stdout output)
        last="''${new[-1]}"
        if [ "$last" = "-" ]; then
          unset 'new[-1]'
          new+=("-ac" "2" "-")
        else
          new+=("-ac" "2")
        fi
      fi
      exec ${pkgs.ffmpeg}/bin/ffmpeg "''${new[@]}"
    else
      exec ${pkgs.ffmpeg}/bin/ffmpeg "$@"
    fi
  '';

  ffmpeg-wrapped = pkgs.runCommand "ffmpeg-navidrome" { } ''
    mkdir -p $out/bin
    ln -s ${ffmpeg-opus-wrapper} $out/bin/ffmpeg
    ln -s ${pkgs.ffmpeg}/bin/ffprobe $out/bin/ffprobe
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
        FFmpegPath = "${ffmpeg-wrapped}/bin/ffmpeg";
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
