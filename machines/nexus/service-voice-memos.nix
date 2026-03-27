{ pkgs, inputs, ... }:
{
  services.surmhosting.services.voice-memos.expose.port = 8080;
  services.surmhosting.services.voice-memos.container = {
    config = {
      system.stateVersion = "25.05";

      systemd.services.voice-memos-server = {
        enable = true;
        description = "Voice Memos server";
        wantedBy = [ "multi-user.target" ];
        environment = {
          STORAGE_DIR = "/dump/state/voice-memos";
          SHARED_SECRET = "test1234";
        };
        serviceConfig = {
          ExecStart = "${inputs.voice-memos.packages.${pkgs.stdenv.system}.backend-server}/bin/voicememos-server";
          User = "containeruser";
          Restart = "always";
        };
      };

      systemd.services.voice-memos-worker = {
        enable = true;
        description = "Voice Memos worker";
        wantedBy = [ "multi-user.target" ];
        environment.STORAGE_DIR = "/dump/state/voice-memos";
        serviceConfig = {
          ExecStart = "${inputs.voice-memos.packages.${pkgs.stdenv.system}.backend-worker}/bin/voicememos-worker";
          User = "containeruser";
          Restart = "always";
        };
      };
    };

    bindMounts.state = {
      mountPoint = "/dump/state/voice-memos";
      hostPath = "/dump/state/voice-memos";
      isReadOnly = false;
    };
  };
}
