{
  config,
  pkgs,
  lib,
  ...
}:
let
  publicKey = ../gpg-keys/key.pub.asc;
  privateKey = ../gpg-keys/key.sec.asc;
  gpg = config.programs.gpg.package;
in
{
  config = {
    home.activation = {
      # --batch surpressed prompting for the key's passphrase
      gpgKeys = lib.hm.dag.entryAfter [ "sshKeys" ] ''
        ${gpg}/bin/gpg --batch --import ${publicKey}        
        cat ${privateKey} | ${pkgs.age}/bin/age --decrypt --identity ${config.home.homeDirectory}/.ssh/id_ed25519 | ${gpg}/bin/gpg --import --batch -
      '';
    };
  };
}
