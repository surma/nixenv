{
  lib,
}:
let
  repeatString = n: str: lib.genList (x: str) n |> lib.concatStrings;

  uuuCommands =
    lib.genList (x: x) 5
    |> map (n: {
      name = "u" |> repeatString (n + 1);
      value = "cd ${"../" |> repeatString (n + 1)}";
    })
    |> lib.listToAttrs;
in
{
  config = {
    enable = true;
    shellAliases = {
      ".." = "cd ..";
      cd = "z";
      u = "cd ..";
    }
    // uuuCommands;
    initContent = ''
      # Nix
      test -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

      # This is needed for gpg+pinentry to work
      export GPG_TTY=$(tty)
      # Only dashes are considered part of a word. 
      # This makes ^w behave more intuitively.
      export WORDCHARS='-'

      # nvm
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 

      # Rustup
      . "$HOME/.cargo/env"
    '';
  };
}
