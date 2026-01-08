{
  keys = {
    surma = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjljY7ksA49iEa/okN+JeqBTHUAVZ9Sr9Zu5fWqCt2N";
    surmbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdkAzY2ZCWso0wySLMlcfY7r8C8JC8b4c0NPM3fnhSV";
    dragoon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdkAzY2ZCWso0wySLMlcfY7r8C8JC8b4c0NPM3fnhSV";
    shopisurm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMK/fhQ4SEVrRem71dZtX0OVqNiZ7f51+XtIC/P30iO";
    surmrock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKJrS5BIQrThWaQK/rJSbFm7WGtsF/M6Z37jlYuO72bf";
    surmedge = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRS1TLlaWODfefGUvk0mYZEx6pE6Gr2xhsVGbsn91Uh";
    pylon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRS1TLlaWODfefGUvk0mYZEx6pE6Gr2xhsVGbsn91Uh";
    surmframework = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHVSc2lTehmhEl87rp3m15b8Q1GojwNJsnbxJxWe99";
    archon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHVSc2lTehmhEl87rp3m15b8Q1GojwNJsnbxJxWe99";
    surmturntable = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBb7S7oe5a61I0TH+2xmI68rGVflyftTvjQlVinJgFOr surma@surmturntable";
    nexus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFSKtxq/1aLxos5lZTWzROCqMLkiVlxKd1jJF0XKGCrW surma@nexus";
  };
  secrets = {
    ssh-keys = {
      contents = ../ssh-keys/id_surma.age;
      keys = [
        "surma"
        "surmbook"
        "surmedge"
        "surmrock"
        "nexus"
        "shopisurm"
        "surmframework"
        "surmturntable"
      ];
    };
    gpg-keys = {
      contents = ../gpg-keys/key.sec.asc.age;
      keys = [
        "surma"
        "surmbook"
        "nexus"
        "surmedge"
        "surmrock"
        "shopisurm"
        "surmframework"
        "surmturntable"
      ];
    };
    writing-prompt = {
      contents = ../apps/writing-prompt/env.age;
      keys = [
        "surma"
        "surmedge"
        "nexus"
      ];
    };
    hate = {
      contents = ../apps/hate/env.age;
      keys = [
        "surma"
        "nexus"
      ];
    };
    nexus-syncthing = {
      contents = ../machines/nexus/syncthing/key.pem.age;
      keys = [
        "surma"
        "nexus"
      ];
    };
    nexus-copyparty = {
      contents = ../machines/nexus/copyparty/surma.passwd.age;
      keys = [
        "surma"
        "nexus"
      ];
    };
    nexus-redis = {
      contents = ../machines/nexus/redis/pw.age;
      keys = [
        "surma"
        "nexus"
        "shopisurm"
      ];
    };
    llm-proxy-secret = {
      contents = ../secrets/llm-proxy-secret.age;
      keys = [
        "surma"
        "nexus"
        "pylon"
        "shopisurm"
      ];
    };
  };
}
