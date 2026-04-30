{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs,
  ...
}:
let
  version = "0.16.2";
in
buildNpmPackage {
  pname = "claude-code-acp";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@zed-industries/claude-code-acp/-/claude-code-acp-${version}.tgz";
    hash = "sha256-RxOzu6BGUIUJKeTbHmgAc9A79V3N+L/LO7HL2CvPqZ4=";
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

  npmDepsHash = "sha256-vmwMKAXOOu8SNdYSav3LTkDVpGXupo5bfUXb+VSxoBI=";
  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible coding agent powered by the Claude Code SDK";
    homepage = "https://github.com/zed-industries/claude-code-acp";
    license = lib.licenses.asl20;
    mainProgram = "claude-code-acp";
  };
}
