{
  pkgs,
  lib,
  ...
}:
{
  config = {
    environment.systemPackages = with pkgs; [
      podman
      shadow
    ];

    environment.etc."containers/policy.json".text =
      {
        default = [
          {
            type = "insecureAcceptAnything";
          }
        ];
      }
      |> builtins.toJSON;

    systemd.generators.podman-system-generator = "${pkgs.podman}/lib/systemd/system-generators/podman-system-generator";
    systemd.user.generators.podman-user-generator = "${pkgs.podman}/lib/systemd/user-generators/podman-user-generator";
  };
}
