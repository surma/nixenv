{
  ...
}:
let
  mkElectronWrapperModule = import ../../lib/make-electron-wrapper-module.nix;
  wrapperMod = mkElectronWrapperModule {
    name = "spotify";
    desktopName = "Spotify";
  };
in
{
  imports = [ wrapperMod ];
}
