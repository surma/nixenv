{
  inputs,
  stdenv,
  ...
}:
inputs.opencode.packages.${stdenv.hostPlatform.system}.default
