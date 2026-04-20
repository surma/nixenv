{
  pkgs,
  config,
  lib,
  systemManager,
  inputs,
  ...
}:
with lib;
let
  cfg = config.programs.parakeet;
  system = pkgs.stdenv.hostPlatform.system;

  # parakeet-mlx on Darwin (Apple Silicon), chough on Linux
  defaultPackage =
    if pkgs.stdenv.hostPlatform.isDarwin
    then inputs.self.packages.${system}.parakeet-mlx
    else inputs.self.packages.${system}.chough;
in
{
  imports = [
    ../../home-manager/parakeet/default-config.nix
  ];

  options = {
    programs.parakeet = {
      enable = mkEnableOption "Parakeet speech-to-text transcription";
      package = mkOption {
        type = types.package;
        default = defaultPackage;
        description = ''
          The parakeet package to use.
          Defaults to parakeet-mlx on macOS and chough on Linux.
        '';
      };
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];
  };
}
