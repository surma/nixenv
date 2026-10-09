{
  writeShellApplication,
  coreutils,
  gnugrep,
  libnotify,
  libva-utils,
  pulseaudio,
  slurp,
  systemd,
  wl-screenrec,
  wl-clipboard,
}:

writeShellApplication {
  name = "record-screen";
  runtimeInputs = [
    coreutils
    gnugrep
    libnotify
    # vainfo
    libva-utils
    # pactl
    pulseaudio
    slurp
    systemd
    wl-screenrec
    wl-clipboard
  ];
  text = builtins.readFile ./record-screen.sh;
}
