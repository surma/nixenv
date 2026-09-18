{
  config,
  nixenv,
  osConfig ? null,
  ...
}:
# Makes this machine a peer in my Syncthing mesh. A peer carries its own
# identity, and both halves follow the peer name: the certificate lives in
# machines/<name>/syncthing/cert.pem, the private key comes from the
# <name>-syncthing item in the secrets registry.
#
# The peer name is the host name, because the alias configurations
# (surmframework, surmbook) reuse another machine's directory and must reuse its
# identity. shopisurm sets no host name, so the configuration name serves there.
let
  peerName =
    if osConfig != null && (osConfig.networking.hostName or null) != null then
      osConfig.networking.hostName
    else
      nixenv.machineName;
  keyItem = "${peerName}-syncthing";
  certFile = ../../../machines + "/${peerName}/syncthing/cert.pem";
in
{
  secrets.items.${keyItem}.target = "${config.home.homeDirectory}/.local/state/syncthing/key.pem";

  services.syncthing.enable = true;
  services.syncthing.cert = certFile |> builtins.toString;
  services.syncthing.key = config.secrets.items.${keyItem}.target;
  defaultConfigs.syncthing.enable = true;
}
