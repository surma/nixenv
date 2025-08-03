{
  fetchFromGitHub,
  pkgs,
  stdenv,
  pnpm,
  lib,
  writeShellScriptBin,
  nodejs ? pkgs.nodejs_24,
  ...
}:
let
  srcHash = "sha256-cV1h138IkfnsBH8055sZch3cm1WUx6vAo0uUQeiNlIY=";
  pnpmDepsHash = "sha256-m7JLJP2GDTWLbnW2x7m82LDPC0/kLzBd4uPChKoxcwU=";

  src = fetchFromGitHub {
    owner = "zcaceres";
    repo = "fetch-mcp";
    rev = "7189766a0d7e75c2b837f93e613f2a15deacac08";
    hash = srcHash;
  };

  packageJson = lib.importJSON "${src}/package.json";
  inherit (packageJson) version;

  postPatch = ''
    cp ${./pnpm-lock.yaml} pnpm-lock.yaml
  '';

  pnpmPackage = stdenv.mkDerivation (final: {
    pname = "fetch-mcp";
    inherit version src postPatch;

    nativeBuildInputs = [
      nodejs
      pnpm.configHook
    ];

    buildPhase = ''
      pnpm build
    '';

    installPhase = ''
      runHook preInstall 

      mkdir -p $out
      cp -r * $out/

      runHook postInstall
    '';

    pnpmDeps = pnpm.fetchDeps {
      inherit (final)
        pname
        version
        src
        postPatch
        ;
      hash = pnpmDepsHash;
    };
  });
in
writeShellScriptBin "fetch-mcp" ''
  ${nodejs}/bin/node ${pnpmPackage}/dist/index.js
''
