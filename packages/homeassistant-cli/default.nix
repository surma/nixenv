{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs,
  ...
}:
let
  version = "2026.8.10";
in
buildNpmPackage {
  pname = "homeassistant-cli";
  inherit version;

  # Use the pre-built npm registry tarball (includes dist/).
  src = fetchurl {
    url = "https://registry.npmjs.org/@unbrained/homeassistant-cli/-/homeassistant-cli-${version}.tgz";
    hash = "sha256-nwlhp3b0F0EBydeANKdkVNzi+chQt4bR0iLuKUfZx5w=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    # Strip devDependencies so buildNpmPackage doesn't try to resolve them
    ${nodejs}/bin/node -e "
      const pkg = require('./package.json');
      delete pkg.devDependencies;
      delete pkg.scripts;
      require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2));
    "
  '';

  npmDepsHash = "sha256-b3sCitiuhR33GOcKrj01lcws4I1CNVYg8msoYi90pMA=";
  dontNpmBuild = true;

  meta = {
    description = "Agent-optimized CLI for Home Assistant with token-efficient output";
    homepage = "https://github.com/unbraind/homeassistant-cli";
    license = lib.licenses.mit;
    mainProgram = "hassio";
  };
}
