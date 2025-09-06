{
  pkgs,
  ...
}:
{
  config = {
    secrets.items.gpg-keys = {
      contents = ../gpg-keys/key.sec.asc.age;
      command = ''
        ${pkgs.gnupg}/bin/gpg --batch --import ${../gpg-keys/key.pub.asc}
        ${pkgs.gnupg}/bin/gpg --batch --import -
      '';
    };
  };
}
