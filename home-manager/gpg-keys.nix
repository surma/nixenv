{
  pkgs,
  ...
}:
{
  config = {
    secrets.items.gpg-keys = {
      command = ''
        ${pkgs.gnupg}/bin/gpg --batch --import ${../gpg-keys/key.pub.asc}
        ${pkgs.gnupg}/bin/gpg --batch --import -
      '';
    };
  };
}
