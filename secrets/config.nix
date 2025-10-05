{
  keys = {
    surma = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjljY7ksA49iEa/okN+JeqBTHUAVZ9Sr9Zu5fWqCt2N";
    surmbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdkAzY2ZCWso0wySLMlcfY7r8C8JC8b4c0NPM3fnhSV";
    shopisurm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMK/fhQ4SEVrRem71dZtX0OVqNiZ7f51+XtIC/P30iO";
    surmrock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKJrS5BIQrThWaQK/rJSbFm7WGtsF/M6Z37jlYuO72bf";
    surmedge = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRS1TLlaWODfefGUvk0mYZEx6pE6Gr2xhsVGbsn91Uh";
    surmframework = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHVSc2lTehmhEl87rp3m15b8Q1GojwNJsnbxJxWe99";
  };
  secrets = {
    ssh-keys = {
      contents = ../ssh-keys/id_surma.age;
      keys = [
        "surma"
        "surmbook"
        "surmedge"
        "surmrock"
        "shopisurm"
        "surmframework"
      ];
    };
    gpg-keys = {
      contents = ../gpg-keys/key.sec.asc.age;
      keys = [
        "surma"
        "surmbook"
        "surmedge"
        "surmrock"
        "shopisurm"
        "surmframework"
      ];
    };
    writing-prompt = {
      contents = ../apps/writing-prompt/env.age;
      keys = [
        "surma"
        "surmedge"
        "surmrock"
      ];
    };
    aria2-token = {
      contents = ../lidarr/aria2-token.age;
      keys = [
        "surma"
        "surmrock"
      ];
    };
    hate = {
      contents = ../apps/hate/env.age;
      keys = [
        "surma"
        "surmrock"
      ];
    };
  };
}
