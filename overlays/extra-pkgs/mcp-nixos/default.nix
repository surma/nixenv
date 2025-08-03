{
  python3,
  fetchFromGitHub,
  lib,
  writeShellScriptBin,
}:
let
  src = fetchFromGitHub {
    owner = "utensils";
    repo = "mcp-nixos";
    rev = "v1.0.0";
    hash = "sha256-NwP+zM1VGLOzIm+mLZVK9/9ImFwuiWhRJ9QK3hGpQsY=";
  };

  pythonPackage = python3.pkgs.buildPythonApplication {
    pname = "mcp-nixos";
    version = "1.0.0";

    inherit src;

    pyproject = true;

    build-system = with python3.pkgs; [
      hatchling
    ];

    dependencies = with python3.pkgs; [
      beautifulsoup4
      httpx
      mcp
      requests
    ];

    pythonImportsCheck = [ "mcp_nixos" ];

    pythonRelaxDeps = [ "beautifulsoup4" ];

    meta = with lib; {
      description = "Model Context Protocol Server for NixOS resources";
      homepage = "https://github.com/utensils/mcp-nixos";
      license = licenses.mit;
      maintainers = [ ];
    };
  };
in
writeShellScriptBin "mcp-nixos" ''
  ${pythonPackage}/bin/mcp-nixos "$@"
''
