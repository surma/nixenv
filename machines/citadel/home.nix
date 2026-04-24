{
  config,
  ...
}:
{
  imports = [
    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/ai.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/nixdev.nix
    ../../profiles/home-manager/workstation.nix
  ];

  home.stateVersion = "25.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#citadel";

  secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";
  defaultConfigs.pi.extensions.proxy.enable = true;

}
