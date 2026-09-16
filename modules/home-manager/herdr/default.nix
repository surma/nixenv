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
  cfg = config.programs.herdr;

  # `herdr --skill` prints the agent skill that belongs to the binary it was
  # printed by, so generating it here keeps the documented CLI surface from
  # drifting away from the installed herdr. Written atomically, and only when
  # the command produced something, so a failure leaves the previous skill in
  # place instead of truncating it.
  writeSkill = pkgs.writeShellScript "herdr-write-skill" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    target="$HOME/.agents/skills/herdr"
    mkdir -p "$target"

    tmp="$(mktemp "$target/.SKILL.md.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    ${lib.getExe' cfg.package "herdr"} --skill > "$tmp"
    [ -s "$tmp" ]
    mv "$tmp" "$target/SKILL.md"
  '';
in
{
  options.programs.herdr = {
    enable = mkEnableOption "Herdr terminal workspace manager for coding agents";
    package = mkOption {
      type = types.package;
      default = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The herdr package to use";
    };
  };

  config = mkIf (systemManager == "home-manager" && cfg.enable) {
    home.packages = [ cfg.package ];

    # Regenerate the agent skill file on every home-manager switch.
    # This keeps the skill file version-matched to the installed herdr binary.
    home.activation.herdr-skill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${writeSkill}
    '';
  };
}
