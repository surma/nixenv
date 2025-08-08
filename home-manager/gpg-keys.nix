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
      # --batch surpresses prompting for the key's passphrase
      gpgKeys = lib.hm.dag.entryAfter [ "write-boundary" ] ''
        ${gpg}/bin/gpg --batch --import ${publicKey}        
        ${pkgs.badage}/bin/badage decrypt -p "$(${pkgs.tmpmemstore}/bin/tmpmemstore retrieve -s ${config.home.homeDirectory}/.cache/tmpmemstore/nixenv.socket)" -i ${privateKey} -o - | ${gpg}/bin/gpg --import --batch -
      '';
    };
  };
}
