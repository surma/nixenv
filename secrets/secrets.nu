#!/usr/bin/env nu

def main [] {
}

def "main recrypt" [] {
  let config = (nix eval --impure --json --expr "import ./secrets/config.nix" | from json)
  $config.secrets | values | each {|secret|
    let contents = (open $secret.contents | age --decrypt -i ~/.ssh/id_machine -i ~/.ssh/id_surma)
    let recepients = ($secret.keys | each {|k| ["-r" ($config.keys | get $k)]} | flatten)
    let resecret = ($contents | age --encrypt ...$recepients -a)
    $resecret | save -f $secret.contents
    $secret.contents
  }
}

def "main encrypt" [
  --keep-original,
  file
] {
  let out = $"($file).age"
  open $file | age --encrypt -R ~/.ssh/id_machine.pub -a | save $out
  if not $keep_original {
    rm $file
  }
  $out
}

def "main genkey" [] {
  ssh-keygen -f ~/.ssh/id_machine -t ed25519 -N ""
  open ~/.ssh/id_machine.pub
}

