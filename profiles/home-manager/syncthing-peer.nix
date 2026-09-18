{
  config,
  nixenv,
  ...
}:
# Makes this machine a peer in my Syncthing mesh. A peer carries its own
# identity, and both halves follow the machine name: the certificate lives in
# machines/<name>/syncthing/cert.pem, the private key comes from the
# <name>-syncthing item in the secrets registry.
let
  keyItem = "${nixenv.machineName}-syncthing";
  certFile = ../../machines + "/${nixenv.machineName}/syncthing/cert.pem";
in
{
  secrets.items.${keyItem}.target = "${config.home.homeDirectory}/.local/state/syncthing/key.pem";

  services.syncthing.enable = true;
  services.syncthing.cert = certFile |> builtins.toString;
  services.syncthing.key = config.secrets.items.${keyItem}.target;
  defaultConfigs.syncthing.enable = true;
}
