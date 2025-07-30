{
  config,
  pkgs,
  lib,
  ...
}:
let
  publicKey = ../ssh-keys/id_ed25519.pub;
  privateKey = ../ssh-keys/id_ed25519;
in
{
  config = {
    home.file.".ssh/id_ed25519.pub".source = publicKey;
    home.activation = {
      sshKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        KEY="${config.home.homeDirectory}/.ssh/id_ed25519"
        if [ ! -f "$KEY" ]; then
          echo "Decrypting SSH key..."
          cat ${privateKey} | ${pkgs.age}/bin/age --decrypt > "$KEY"
        fi
      '';
    };
  };
}
