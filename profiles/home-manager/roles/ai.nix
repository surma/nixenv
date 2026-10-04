{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../../modules/home-manager/herdr
  ];

  # Installs herdr and regenerates ~/.agents/skills/herdr/SKILL.md from
  # `herdr --skill` on every switch, so the skill matches the binary.
  programs.herdr.enable = true;

  # The native herdr client, on Linux machines with a desktop. The flake has
  # no macOS build, and headless machines cannot open it.
  programs.herdr.gui.enable = lib.mkDefault (pkgs.stdenv.hostPlatform.isLinux && config.nixenv.gui);

  defaultConfigs.herdr.enable = true;

  defaultConfigs.agents.enable = true;

  programs.pi.enable = true;
  defaultConfigs.pi.enable = true;
  secrets.items.openrouter-api-key.target = "${config.home.homeDirectory}/.local/state/openrouter-api-key";
  defaultConfigs.pi.openRouter.keyFile = config.secrets.items.openrouter-api-key.target;

  programs.web-search-cli.enable = true;
  defaultConfigs.web-search-cli.enable = true;

  programs.agent-browser.enable = true;

  defaultConfigs.pi.settings.enableSkillCommands = true;
  defaultConfigs.pi.extensions.skillAliases.enable = true;

  agent.skills = [
    # ../../../assets/skills/brainstorming
    # ../../../assets/skills/planning
    # ../../../assets/skills/debugging
    ../../../assets/skills/simplify
    ../../../assets/skills/surma-writer
    ../../../assets/skills/rust
    ../../../assets/skills/triple-helix
    ../../../assets/skills/preact-signals
    ../../../assets/skills/web-development
    ../../../assets/skills/bro
  ];

  # Every role directory in assets/roster, so a new role needs no change here.
  agent.roster =
    let
      rosterDir = ../../../assets/roster;
    in
    builtins.readDir rosterDir
    |> lib.filterAttrs (_: type: type == "directory")
    |> lib.attrNames
    |> map (name: rosterDir + "/${name}");
}
