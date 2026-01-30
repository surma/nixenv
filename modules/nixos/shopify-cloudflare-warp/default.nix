{
  pkgs,
  ...
}:
{

  # unfree-apps now globally injected as a feature module
  allowedUnfreeApps = [
    "cloudflare-warp"
  ];
  environment.systemPackages = with pkgs; [
    cloudflare-warp
  ];
  systemd.packages = with pkgs; [ cloudflare-warp ];
  systemd.services.warp-svc.enable = true;

}
