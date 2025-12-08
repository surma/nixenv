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
  srcHash = "sha256-+d1bvWsttEmoqNWu79DcrXMdh3LW/iSF2YaQz68Gi6g";
  pnpmDepsHash = "sha256-MnzlGcLiXrpMUzzqN4wXB9d/rhhO/00zlORZ1HPM7fI=";

  src = fetchFromGitHub {
    owner = "zcaceres";
    repo = "fetch-mcp";
    rev = "c662c8ac300f715e414a64766cd95cc9ec60a1b3";
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
      fetcherVersion = 2;
    };
  });
in
writeShellScriptBin "fetch-mcp" ''
  ${nodejs}/bin/node ${pnpmPackage}/dist/index.js
''
