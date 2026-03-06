{ config, lib, ... }:
{
  imports = [
    ../../profiles/home-manager/base.nix
    ../../profiles/home-manager/dev.nix
    ../../profiles/home-manager/linux.nix
    ../../profiles/home-manager/workstation.nix
  ];

  secrets.identity = "${config.home.homeDirectory}/.ssh/id_machine";
  secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

  home.stateVersion = "25.05";

  home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#scout";

  # Best-effort linger enablement for user services to survive logout.
  home.activation.enableLinger = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if command -v loginctl >/dev/null 2>&1; then
      if [ "$(loginctl show-user ${config.home.username} --property=Linger --value 2>/dev/null || true)" != "yes" ]; then
        loginctl enable-linger ${config.home.username} >/dev/null 2>&1 || true
      fi
    fi
  '';

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
}
