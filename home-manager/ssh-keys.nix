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
    # home.activation = {
    #   sshKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    #     KEY="${config.home.homeDirectory}/.ssh/id_ed25519"
    #     ${pkgs.badage}/bin/badage decrypt -p "$(${pkgs.tmpmemstore}/bin/tmpmemstore retrieve -s ${config.home.homeDirectory}/.cache/tmpmemstore/nixenv.socket)" -i ${privateKey} -o "$KEY"
    #   '';
    # };
  };
}
