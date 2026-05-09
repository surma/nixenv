{ ... }:
let
  ports = import ./ports.nix;
in
{
  users.users.surma.linger = true;

  services.surmhosting.services.terminal = {
    host = "localhost";
    expose.port = ports.zellijWeb;
  };
}
