{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  inherit (pkgs) writeShellScriptBin makeDesktopItem symlinkJoin;

  webapp = (
    { config, ... }:
    {
      options = {
        url = mkOption {
          type = types.str;
        };
        title = mkOption {
          type = types.nullOr types.str;
          default = config.url;
        };
      };
    }
  );

  buildWebApp =
    {
      runner,
      name,
      webapp,
    }@args:
    let
      bin = writeShellScriptBin name (runner.invocation args);
      desktopItem = makeDesktopItem {
        inherit name;
        desktopName = webapp.title;
        exec = "${bin}/bin/${name}";
      };
    in
    symlinkJoin {
      inherit name;
      paths = [
        bin
        desktopItem
      ];
    };

in
{
  options = {
    programs.webapps = {
      runner = {
        package = mkOption {
          type = types.package;
          default = pkgs.chromium;
        };
        profileName = mkOption {
          type = types.str;
          default = "webapps";
        };
        platform = mkOption {
          type =
            with types;
            enum [
              "wayland"
              "x11"
              "auto"
            ];
          default = "wayland";
        };
        invocation = mkOption {
          type = with types; functionTo str;
          default = (
            { runner, webapp, ... }:
            "${runner.package}/bin/chromium --user-data-dir=$HOME/.config/chromium/${runner.profileName} --ozone-platform=${runner.platform} --new-window --app=${webapp.url} --name=${webapp.title}"
          );
        };
      };
      apps = mkOption {
        type = with types; attrsOf (submodule webapp);
        default = { };
      };
    };
  };
  config =
    let
      inherit (config.programs.webapps) apps runner;

      appPackages =
        apps
        |> lib.attrsToList
        |> lib.map (
          { name, value }:
          buildWebApp {
            inherit name runner;
            webapp = value;
          }
        );
    in
    {
      home.packages = appPackages;
    };
}
