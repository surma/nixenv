{
  pkgs,
  config,
  ...
}:
let
  uid = config.users.users.surma.uid;
in
{
  services.surmhosting.exposedApps.prowlarr.target = {
    cfg = {
      system.stateVersion = "25.05";
      users.users.containeruser = {
        inherit uid;
        isNormalUser = true;
      };

      services.prowlarr.enable = true;
      services.prowlarr.package = pkgs.prowlarr;
      services.prowlarr.settings.server.port = 8080;

    };

    extraContainerCfg.bindMounts.state = {
      mountPoint = "/var/lib/private/prowlarr";
      hostPath = "/dump/state/prowlarr";
      isReadOnly = false;
    };
  };
}
