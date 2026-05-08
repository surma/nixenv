{
  lib,
  config,
  systemManager,
  ...
}:
let
  inherit (lib) mkDefault;

  configuredIdentity = toString config.secrets.identity;
  expandedDefaultIdentity =
    if systemManager == "home-manager" then
      "${config.home.homeDirectory}/.ssh/id_machine"
    else if systemManager == "nix-darwin" then
      "/var/root/.ssh/id_machine"
    else
      "/root/.ssh/id_machine";

  identityPath = if configuredIdentity == "~/.ssh/id_machine" then expandedDefaultIdentity else configuredIdentity;
in
{
  config.sops.age.sshKeyPaths = mkDefault [ identityPath ];
}
