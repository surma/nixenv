{
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ../../profiles/nixos/base.nix

    ../../modules/nixos/hyprland
    ../../modules/nixos/1password-wrapper
  ];

  allowedUnfreeApps = [
    "1password"
    "1password-cli"
  ];

  networking.hostName = "citadel";

  nix.settings.require-sigs = false;
  nix.settings.max-jobs = 4;
  nix.settings.cores = 2;
  secrets.identity = "/home/surma/.ssh/id_machine";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  # Serial debug console on UART2 (40-pin header pins 8/10, GND on pin 6).
  # 1.5 Mbaud matches what the DT's chosen/stdout-path advertises and what
  # BL31/EDK2 use, so we get a continuous output stream from firmware through
  # to userspace with no baud rate switch in the middle.
  # earlycon covers the gap between firmware and full kernel init -- the
  # exact window in which fusb302-test crashes on the MBP charger.
  boot.kernelParams = [
    "earlycon=uart8250,mmio32,0xfeb50000"
    "console=tty1"
    "console=ttyS2,1500000n8"
  ];

  # Serial getty so we can log in over the UART if the network is down.
  systemd.services."serial-getty@ttyS2".enable = true;

  # Cap RK3588 big-core max OPP at 2016 MHz to avoid hard-reset brownouts under
  # combined CPU + NVMe write load (see Brain: citadel-25b48j44).
  # Verified 2026-04-25: kitchen-sink stress (cpu8 + vm + io + hdd-fsync) survives
  # at 2016 MHz / 0.925 V; crashes within ~15s at 2208 MHz / 0.9875 V or
  # 2400 MHz / 1.000 V. Both A76 clusters at the top OPP plus PCIe-NVMe write
  # bursts exceed the available VBUS current budget the EDK2-negotiated PD
  # contract provides, and VBUS collapses (instant power-off, no kernel notice).
  systemd.services.cap-big-core-freq = {
    description = "Cap RK3588 big-core max frequency (brownout mitigation)";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for p in /sys/devices/system/cpu/cpufreq/policy4 /sys/devices/system/cpu/cpufreq/policy6; do
        if [ -w "$p/scaling_max_freq" ]; then
          echo 2016000 > "$p/scaling_max_freq"
        fi
      done
    '';
  };

  networking.firewall.enable = false;
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    hyprlock
    pavucontrol
    hyprsunset
    pciutils
    usbutils
  ];

  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "surma" ];

  programs.obs.enable = true;
  programs.firefox.enable = true;
  programs.signal.enable = true;

  security.polkit.enable = true;
  security.pam.services.hyprlock = { };

  users.users.surma.extraGroups = [
    "networkmanager"
    "wheel"
    "input"
    "video"
    "audio"
  ];

  services.udisks2.enable = true;

  system.stateVersion = "25.05";

  home-manager.users.surma = import ./home.nix;
}
