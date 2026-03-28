{
  pkgs,
  lib,
  inputs,
  authTokenFile ? null,
  perplexityApiBase ? "https://vendors.llm.surma.technology/perplexity",
  browserExecutable ? null,
}:
let
  tokenExportCommand =
    if authTokenFile == null then
      null
    else
      "if [ -f \"${authTokenFile}\" ]; then export WEB_SEARCH_AUTH_TOKEN=\"$(<\"${authTokenFile}\")\"; fi";

  browserExportCommand = lib.optionalString (browserExecutable != null) ''
    export CHROME_EXECUTABLE_PATH="${browserExecutable}"
  '';

  wrapperArgs =
    [ "--set WEB_SEARCH_PERPLEXITY_API_BASE ${lib.escapeShellArg perplexityApiBase}" ]
    ++ lib.optional (tokenExportCommand != null) "--run ${lib.escapeShellArg tokenExportCommand}"
    ++ lib.optional (browserExportCommand != "") "--run ${lib.escapeShellArg browserExportCommand}";
in
pkgs.symlinkJoin {
  name = "web-search-cli-wrapped";
  paths = [ inputs.web-search-cli.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/web-search ${lib.concatStringsSep " " wrapperArgs}
  '';
}
