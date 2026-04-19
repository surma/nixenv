{ ... }:
let
  port = 8092;
in
{
  imports = [
    ../../modules/services/nixos-deploy
  ];

  services.nixos-deploy = {
    enable = true;
    listenAddress = "127.0.0.1:${toString port}";
    flakeURL = "github:surma/nixenv#nexus";
  };

  services.surmhosting.services.nixos-deploy = {
    host = "localhost";
    expose.port = port;
  };
}
