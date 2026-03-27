{ ... }:
{
  services.surmhosting.auth = {
    domain = "auth.surma.technology";
    github.clientIdFile = "/var/lib/surm-auth/github-client-id";
    github.clientSecretFile = "/var/lib/surm-auth/github-client-secret";
    cookieSecretFile = "/var/lib/surm-auth/cookie-secret";
    cookieDomain = ".surma.technology";
  };

  secrets.items.surm-auth-github-client-id = {
    target = "/var/lib/surm-auth/github-client-id";
    mode = "0644";
  };
  secrets.items.surm-auth-github-client-secret = {
    target = "/var/lib/surm-auth/github-client-secret";
    mode = "0644";
  };
  secrets.items.surm-auth-cookie-secret = {
    target = "/var/lib/surm-auth/cookie-secret";
    mode = "0644";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/surm-auth 0755 root root -"
  ];
}
