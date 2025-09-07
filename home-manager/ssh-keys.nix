{
  config,
  ...
}:
{
  config = {
    secrets.items.ssh-keys = {
      command = ''
        install -m 0644 ${../ssh-keys/id_surma.pub} ${config.home.homeDirectory}/.ssh/id_surma.pub
        cat > ${config.home.homeDirectory}/.ssh/id_surma
        chmod 0600 ${config.home.homeDirectory}/.ssh/id_surma
      '';
    };
  };
}
