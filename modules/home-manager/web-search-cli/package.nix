{
  pkgs,
  lib,
  inputs,
  authTokenFile ? null,
  perplexityApiBase ? "https://vendors.llm.surma.technology/perplexity",
}:
let
  tokenExportCommand =
    if authTokenFile == null then
      null
    else
      "if [ -f \"${authTokenFile}\" ]; then export WEB_SEARCH_AUTH_TOKEN=\"$(<\"${authTokenFile}\")\"; fi";

  wrapperArgs =
    [ "--set WEB_SEARCH_PERPLEXITY_API_BASE ${lib.escapeShellArg perplexityApiBase}" ]
    ++ lib.optional (tokenExportCommand != null) "--run ${lib.escapeShellArg tokenExportCommand}";
in
pkgs.symlinkJoin {
  name = "web-search-cli-wrapped";
  paths = [ inputs.web-search-cli.packages.${pkgs.system}.default ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/web-search ${lib.concatStringsSep " " wrapperArgs}
  '';
}
