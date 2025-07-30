{
  writeShellScriptBin,
  cpio,
  coreutils,
  age,
  findutils,
  symlinkJoin,
}:
let
  decrypt-secrets = writeShellScriptBin "decrypt-secrets" ''
    PATH=${coreutils}/bin:${cpio}/bin:${age}/bin

    set -e

    mkdir -p $HOME/.secrets
    chmod 0700 $HOME/.secrets
    cd $HOME/.secrets
    cat ${./secrets.cpio.enc} | age -d | cpio -i 
  '';
  encrypt-secrets = writeShellScriptBin "encrypt-secrets" ''
    PATH=${coreutils}/bin:${cpio}/bin:${age}/bin:${findutils}/bin

    set -e

    cd $HOME/.secrets
    find . | cpio -o | age -p -a -e
  '';
in
symlinkJoin {
  name = "secret-scripts";
  paths = [
    decrypt-secrets
    encrypt-secrets
  ];
}
