{ config, pkgs, ... }:

let
  inherit (pkgs) writeShellScript kmod;
  modName = "mt7925e";

  unloadScript = writeShellScript "unload-wifi" ''
    ${kmod}/bin/rmmod ${modName}
  '';
  loadScript = writeShellScript "load-wifi" ''
    ${kmod}/bin/modprobe ${modName}
  '';
in
{
  systemd.services.unload-wifi-presuspend = {
    enable = true;
    description = "Unload the wifi module to allow suspend";
    before = [ "suspend.target" ];
    wantedBy = [ "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${unloadScript}";
    };
  };

  systemd.services.load-wifi-postsuspend = {
    enable = true;
    description = "Load the wifi module after resuming";
    after = [ "suspend.target" ];
    wantedBy = [ "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${loadScript}";
    };
  };
}
