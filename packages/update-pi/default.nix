{
  writeShellApplication,
  nix-update,
  ...
}:
writeShellApplication {
  name = "update-pi";
  runtimeInputs = [ nix-update ];
  text = ''
    exec nix-update --flake --custom-dep modelData --build pi-coding-agent "$@"
  '';
}
