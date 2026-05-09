{ ... }:
{
  users.users.surma.linger = true;

  services.surmhosting.services.terminal = {
    host = "localhost";
    expose.port = 8082;
  };
}
