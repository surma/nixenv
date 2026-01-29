#!/usr/bin/env nu

# Helper function to determine the flake root
def get-root [root?: string] {
  if $root != null {
    $root
  } else {
    git rev-parse --show-toplevel | str trim
  }
}

# Secrets management tool for age-encrypted files
def main [] {
  # Nushell will auto-generate help with subcommands
}

# Re-encrypt secrets with updated public keys
#
# This command reads the secrets configuration and re-encrypts
# all secrets (or specific ones) with the current set of public
# keys defined in secrets/config.nix. Useful after adding or
# removing machines from the key list.
def "main recrypt" [
  --root (-r): string  # Path to flake root (defaults to git root)
  ...files: string     # Specific secret names to recrypt (optional, recrypts all if empty)
] {
  let flake_root = (get-root $root)
  let config = (nix eval --impure --json --expr $"import ($flake_root)/secrets/config.nix" | from json)
  let secrets = if ($files | is-empty) {
    $config.secrets | values
  } else {
    $config.secrets | transpose key value | where {|secret| $secret.key in $files } | get value 
  }
  $secrets | each {|secret|
    let recepients = ($secret.keys | each {|k| ["-r" ($config.keys | get $k)]} | flatten)
    let resecret = (open -r $secret.contents | age --decrypt -i ~/.ssh/id_machine -i ~/.ssh/id_surma | age --encrypt ...$recepients -a)
    $resecret | save -rf $secret.contents
    $secret.contents
  }
}

def encrypt [
  keep_original: bool
  out: string
  file: string
] {
  open -r $file | age --encrypt -R ~/.ssh/id_machine.pub -a | save -rf $out
  if not $keep_original {
    rm $file
  }
  $out
}

# Encrypt a file using age
#
# Encrypts a plaintext file using the local machine's public key.
# By default, the encrypted file will have a .age extension and
# the original will be deleted. Use --keep-original to preserve it.
def "main encrypt" [
  --root (-r): string      # Path to flake root (defaults to git root)
  --keep-original          # Keep the original unencrypted file
  --target (-t): string    # Target output file (defaults to <file>.age)
  file: string             # File to encrypt
] {
  let out = if $target == null {$"($file).age"} else {$target}
  encrypt $keep_original $out $file
}

# Edit an encrypted secret file
#
# Decrypts the file to a temporary location, opens it in $EDITOR,
# then re-encrypts it with the local machine's key. After editing,
# run 'recrypt' to update the file with all authorized public keys.
def "main edit" [
  --root (-r): string  # Path to flake root (defaults to git root)
  file: string         # Encrypted file to edit
] {
  let tmp = (mktemp)
  open -r $file | age --decrypt -i ~/.ssh/id_machine -i ~/.ssh/id_surma | save -rf $tmp
  ^$env.EDITOR $tmp
  encrypt false $file $tmp
  print "The secret was encrypted for the local machine. To apply the public keys, run `recrypt`"
}

# Generate a new machine SSH key for age encryption
#
# Creates a new ed25519 SSH key pair at ~/.ssh/id_machine.
# The public key is displayed and should be added to
# secrets/config.nix in the keys section.
def "main genkey" [
  --root (-r): string  # Path to flake root (defaults to git root)
] {
  ssh-keygen -f ~/.ssh/id_machine -t ed25519 -N ""
  open ~/.ssh/id_machine.pub
}

