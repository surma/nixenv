{
  config,
  pkgs,
  inputs,
  ...
}:
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  config = {

    home.packages = (with pkgs; [ ffmpeg ]);
    programs.yt-dlp.enable = true;
    programs.yt-dlp.package = pkgs-unstable.yt-dlp;
  };
}
