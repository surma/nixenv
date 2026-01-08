{
  pkgs,
  ...
}:
{

  imports = [
    ../home-manager/unfree-apps.nix
  ];
  allowedUnfreeApps = [
    "cloudflare-warp"
  ];
  environment.systemPackages = with pkgs; [
    cloudflare-warp
  ];
  systemd.packages = with pkgs; [ cloudflare-warp ];
  systemd.services.warp-svc.enable = true;

}
