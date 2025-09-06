{
  secrets = {
    ssh-keys = {
      contents = ../ssh-keys/id_surma.age;
      keys = [
        "surma"
        "surmbook"
      ];
    };
    gpg-keys = {
      contents = ../gpg-keys/key.sec.asc.age;
      keys = [
        "surma"
        "surmbook"
      ];
    };
  };
  keys = {
    surma = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjljY7ksA49iEa/okN+JeqBTHUAVZ9Sr9Zu5fWqCt2N";
    surmbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdkAzY2ZCWso0wySLMlcfY7r8C8JC8b4c0NPM3fnhSV";
    shopisurm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMK/fhQ4SEVrRem71dZtX0OVqNiZ7f51+XtIC/P30iO";
    surmrock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJ4RIf0IWWtOwHLvLcYBWb6dqWUnrJ1j72bDjbVoRmq";
    surmedge = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRS1TLlaWODfefGUvk0mYZEx6pE6Gr2xhsVGbsn91Uh";
  };
}
