{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    services.keyd.treat-as-internal-keyboard = mkEnableOption "";
  };
  config = {
    environment.etc."libinput/local-overrides.quirks".text =
      mkIf (config.services.keyd.treat-as-internal-keyboard) ''
        [Virtual Keyboard]
        MatchUdevType=keyboard
        MatchName=keyd virtual keyboard
        AttrKeyboardIntegration=internal
      '';
  };
}
