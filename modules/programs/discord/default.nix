{
  ...
}:
let
  mkElectronWrapperModule = import ../../lib/make-electron-wrapper-module.nix;
  wrapperMod = mkElectronWrapperModule {
    name = "discord";
    desktopName = "Discord";
  };
in
{
  imports = [ wrapperMod ];
}
