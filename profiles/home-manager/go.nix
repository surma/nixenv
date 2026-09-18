{
  pkgs,
  ...
}:
# The Go toolchain and its language server. Machines that also build cgo code
# add a compiler themselves.
{
  programs.go.enable = true;
  home.packages = with pkgs; [
    gopls
  ];
}
