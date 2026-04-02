{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  ...
}:
let
  version = "0.23.4";

  sources = {
    x86_64-linux = "bin/agent-browser-linux-x64";
    aarch64-linux = "bin/agent-browser-linux-arm64";
    x86_64-darwin = "bin/agent-browser-darwin-x64";
    aarch64-darwin = "bin/agent-browser-darwin-arm64";
  };

  binaryPath =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin");
in
stdenv.mkDerivation {
  pname = "agent-browser";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
    hash = "sha512-FSCjFL+szDz/oWkBv80WnRJyISXD101ePeB8ReuaeGCF5VaiKTrLHccyCeXI8j+DMG6Gt3VU9E0OHvRXKaA+XA==";
  };

  sourceRoot = "package";

  nativeBuildInputs = lib.optionals stdenv.isLinux [ patchelf ];
  dontPatchELF = true;
  dontStrip = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/pi/skills
    cp ${binaryPath} $out/bin/agent-browser
    cp -R skills/agent-browser $out/share/pi/skills/
    chmod +x $out/bin/agent-browser

    ${lib.optionalString stdenv.isLinux ''
      patchelf \
        --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
        $out/bin/agent-browser
    ''}

    runHook postInstall
  '';

  meta = {
    description = "Browser automation CLI for AI agents";
    homepage = "https://agent-browser.dev";
    downloadPage = "https://www.npmjs.com/package/agent-browser";
    license = lib.licenses.asl20;
    mainProgram = "agent-browser";
    platforms = builtins.attrNames sources;
  };
}
