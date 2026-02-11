{
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  piEnabled = config.programs.pi.enable;
  superpowers = inputs.pi-superpowers;

  mkLinks =
    base: entries:
    mapAttrs'
      (
        name: type:
        nameValuePair ".pi/agent/${base}/${name}" {
          source = "${superpowers}/${base}/${name}";
        }
      )
      (
        filterAttrs (
          _: type:
          builtins.elem type [
            "regular"
            "directory"
          ]
        ) entries
      );

  skillLinks = mkLinks "skills" (builtins.readDir "${superpowers}/skills");
  extensionLinks = mkLinks "extensions" (builtins.readDir "${superpowers}/extensions");
in
{
  config = mkIf (systemManager == "home-manager" && piEnabled) {
    home.file = mkMerge [
      skillLinks
      extensionLinks
    ];
  };
}
