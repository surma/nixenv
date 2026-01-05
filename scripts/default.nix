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
  scripts = builtins.readDir src |> lib.filterAttrs (name: _v: !lib.strings.hasSuffix ".nix" name);

  makeCrossPlatformDesktopItem =
    pkgs.callPackage (import ../lib/make-cross-platform-desktop-item.nix)
      { };

  packages = [
    (callPackage (import ./flacsplit) { })
  ]
  ++ (
    scripts
    |> lib.attrsToList
    |> lib.filter ({ name, ... }: config.customScripts.${name}.enable)
    |> lib.map (
      { name, ... }:
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
      }
    )
  );
in
{
  options = {
    customScripts =
      scripts
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
