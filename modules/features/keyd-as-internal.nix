{
  lib,
  config,
  systemManager,
  ...
}:
with lib;
{
  options = {
    services.keyd.treat-as-internal-keyboard = mkEnableOption "Treat keyd virtual keyboard as internal";
  };

  config = mkIf (systemManager == "nixos" && config.services.keyd.treat-as-internal-keyboard) {
    environment.etc."libinput/local-overrides.quirks".text = ''
      [Virtual Keyboard]
      MatchUdevType=keyboard
      MatchName=keyd virtual keyboard
      AttrKeyboardIntegration=internal
    '';
  };
}
