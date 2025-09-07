#!/usr/bin/env nu

def main [] {
}

def "main recrypt" [] {
  let config = (nix eval --impure --json --expr "import ./secrets/config.nix" | from json)
  $config.secrets | values | each {|secret|
    let recepients = ($secret.keys | each {|k| ["-r" ($config.keys | get $k)]} | flatten)
    let resecret = (open -r $secret.contents | age --decrypt -i ~/.ssh/id_machine -i ~/.ssh/id_surma | age --encrypt ...$recepients -a)
    $resecret | save -rf $secret.contents
    $secret.contents
  }
}

def encrypt [
  keep_original
  out
  file
] {
  open -r $file | age --encrypt -R ~/.ssh/id_machine.pub -a | save -rf $out
  if not $keep_original {
    rm $file
  }
  $out
}

def "main encrypt" [
  --keep-original,
  --target (-t): string,
  file
] {
  let out = if $target == null {$"($file).age"} else {$target}
  encrypt $keep_original $out $file
}

def "main edit" [
  --keep-original,
  file
] {
  let tmp = (mktemp)
  open -r $file | age --decrypt -i ~/.ssh/id_machine -i ~/.ssh/id_surma | save -rf $tmp
  ^$env.EDITOR $tmp
  encrypt false $file $tmp
  print "The secret was encrypted for the local machine. To apply the public keys, run `recrypt`"
}

def "main genkey" [] {
  ssh-keygen -f ~/.ssh/id_machine -t ed25519 -N ""
  open ~/.ssh/id_machine.pub
}

