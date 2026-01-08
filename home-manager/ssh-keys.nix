{
  config,
  ...
}:
{
  config = {
    secrets.items.ssh-keys = {
      command = ''
        install -m 0644 ${../assets/ssh-keys/id_surma.pub} ${config.home.homeDirectory}/.ssh/id_surma.pub
        cat > ${config.home.homeDirectory}/.ssh/id_surma
        # Add a new line at the end. Working around a bug in either age or my nu script here.
        echo >> ${config.home.homeDirectory}/.ssh/id_surma
        chmod 0600 ${config.home.homeDirectory}/.ssh/id_surma
      '';
    };
  };
}
