{
  pkgs,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
in
{
  home.packages =
    (with pkgs; [
      google-cloud-sdk
      opentofu
    ])
    ++ (with pkgs-unstable; [
      podman
      podman-compose
    ]);

  xdg.configFile = {
    "containers/policy.json".text = builtins.toJSON {
      default = [ { type = "insecureAcceptAnything"; } ];
    };
    "containers/registries.conf".text = ''
      unqualified-search-registries = ['docker.io']

      [[registry]]
      prefix = "docker.io"
      location = "docker.io"
    '';
  };
}
