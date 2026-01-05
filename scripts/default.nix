{
  config,
  pkgs,
  lib,
  systemManager,
  ...
}:
with lib;
let
  inherit (pkgs)
    nushell
    stdenv
    symlinkJoin
    callPackage
    ;

  src = ./.;
  dirContents = builtins.readDir src;

  # Simple scripts: files that don't end in .nix
  simpleScripts =
    dirContents
    |> lib.filterAttrs (name: type: !lib.strings.hasSuffix ".nix" name && type != "directory");

  # Complex scripts: directories containing a default.nix
  complexScripts =
    dirContents
    |> lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists "${src}/${name}/default.nix"
    );

  allScripts = simpleScripts // complexScripts;

  makeCrossPlatformDesktopItem =
    pkgs.callPackage (import ../lib/make-cross-platform-desktop-item.nix)
      { };

  mkPackageWithDesktopItem =
    name:
    let
      inherit (config.customScripts.${name}) package;
      desktopItem = makeCrossPlatformDesktopItem {
        inherit name;
        desktopName = name;
        exec = "${package}/bin/${name}";
      };
    in
    symlinkJoin {
      inherit name;
      paths = [ package ] ++ lib.optional config.customScripts.${name}.asDesktopItem desktopItem;
    };

  packages =
    allScripts
    |> lib.attrsToList
    |> lib.filter ({ name, ... }: config.customScripts.${name}.enable)
    |> lib.map ({ name, ... }: mkPackageWithDesktopItem name);
in
{
  options = {
    customScripts =
      (
        simpleScripts
        |> lib.mapAttrs (
          name: _v: {
            enable = mkEnableOption "";
            asDesktopItem = mkEnableOption "";
            package = mkOption {
              type = types.package;
              default = stdenv.mkDerivation {
                name = "custom-script-${name}";
                src = "${src}/${name}";
                nixenvsrc = ../.;
                dontUnpack = true;
                buildInputs = [ nushell ];
                installPhase = ''
                  mkdir -p $out/bin
                  cp $src $out/bin
                  patchShebangs $out/bin/*
                  chmod +x $out/bin/*

                  substituteInPlace $out/bin/* --replace "@NIXENVSRC@" "$nixenvsrc"
                '';
              };
            };
          }
        )
      )
      // (
        complexScripts
        |> lib.mapAttrs (
          name: _v: {
            enable = mkEnableOption "";
            asDesktopItem = mkEnableOption "";
            package = mkOption {
              type = types.package;
              default = callPackage (import "${src}/${name}") { };
            };
          }
        )
      );
  };
  config =
    if systemManager == "nix-darwin" then
      {
        environment.systemPackages = packages;
      }
    else
      { home.packages = packages; };
}
