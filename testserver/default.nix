{
  lib,
  buildNpmPackage,
  pkgs,
  nodejs ? pkgs.nodejs_24,
}:
let
  src = ./.;
  packageJson = "${src}/package.json" |> lib.importJSON;
in
buildNpmPackage {
  pname = packageJson.name;
  version = packageJson.version;
  inherit src nodejs;
  dontNpmBuild = true;
  postBuild = ''
    mkdir node_modules
  '';
  npmDepsHash = "sha256-l4aKfXkph6kgRR51WtrAP0kLZOoTENwwQzI7AUqG7QI=";
  forceEmptyCache = true;
}
