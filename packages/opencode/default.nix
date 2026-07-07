{
  inputs,
  stdenv,
  lib,
  ...
}:
let
  unstableBun = inputs.nixpkgs-unstable.legacyPackages.${stdenv.hostPlatform.system}.bun;
in
inputs.opencode.packages.${stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  # Upstream opencode now relaxes the bun version check itself (postPatch), so
  # our previous relax-bun-version-check.patch is redundant and would make
  # upstream's --replace-fail substitution miss its target.
  nativeBuildInputs = [
    unstableBun
  ]
  ++ lib.filter (pkg: (pkg.pname or "") != "bun") (old.nativeBuildInputs or [ ]);
})
