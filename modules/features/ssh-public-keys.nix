{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.sshPublicKeys = mkOption {
    type = types.attrsOf types.str;
    default = import ../../keys/ssh.nix;
    description = "Public SSH keys used across nixenv.";
  };
}
