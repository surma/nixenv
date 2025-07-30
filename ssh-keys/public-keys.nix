{
  lib,
}:
[
  (lib.readFile ./id_ed25519.pub)
  (lib.readFile ./id_rsa.pub)
]
