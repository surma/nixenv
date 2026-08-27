{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.home-manager.nixosModules.home-manager

    ./hardware.nix

    ../../profiles/nixos/base.nix
    ../../modules/nixos/hyprland

    ../../modules/nixos/framework/suspend-fix.nix
    ../../modules/nixos/framework/wifi-fix.nix

    ../../modules/nixos/1password-wrapper

    # Everything Shopify — WARP, Fleet/orbit, Chrome CBCM, Minerva TPM device
    # trust, Endpoint Verification, the FHS shims and the apt-get shim — now
    # lives in one self-contained module. What used to be
    # machines/archon/minerva*.{nix,sh}, machines/archon/endpoint-verification.nix
    # and six cherry-picked shopify-framework modules is the block below.
    inputs.shopify-framework.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.libinput.touchpad.disableWhileTyping = true;

  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.sunshine = {
    enable = true;
    # The NixOS module's generic graphical-session.target also runs in the
    # GDM greeter's user manager. Start Sunshine from the Hyprland-only target
    # in machines/archon/home.nix instead.
    autoStart = false;
    openFirewall = true;
    settings = {
      capture = "wlr";
      origin_web_ui_allowed = "wan";
    };
  };

  services.seatd.enable = true;

  services.keyd = {
    enable = true;
    treat-as-internal-keyboard = true;
    keyboards."internal" = {
      ids = [ "0001:0001" ];
      settings = {
        main = {
          capslock = "overload(meh, escape)";
          leftalt = "leftmeta";
          leftmeta = "leftalt";
        };
        "meh:C-A-M" = { };
      };
    };
  };

  networking.hostName = "archon"; # Define your hostname.

  ####################################################################
  # Shopify developer laptop
  ####################################################################
  # Everything else — endpoints, CA common names, TPM handles, PKCS#11
  # labels, the orbit PATH, the FHS shims — has correct defaults in the
  # module. See `inputs.shopify-framework`'s README for the full option
  # table.
  shopify-framework = {
    enable = true;
    user = "surma";
    idpUsername = "surma@shopify.com";

    # PATHS, never values. The module reads these at activation time as
    # root; nothing about them reaches the world-readable Nix store. Both
    # are produced by the `secrets.items` entries below.
    chrome.enrollmentTokenFile = "/run/shopify-framework/chrome-enrollment-token";
    chrome.enrollmentTokenUnits = [ "secrets.service" ];

    # The Nix option renders the Chrome policy key
    # `CloudManagementEnrollmentOptions`, which is NOT a valid managed-policy
    # key on Linux: `chrome://policy` reports it as Status Error, while the
    # sibling token key reports OK. The Windows equivalent
    # (`CloudManagementEnrollmentMandatory`) is a registry value; on Linux
    # Chrome documents the equivalent as a *file* at
    # `/etc/opt/chrome/policies/enrollment/CloudManagementEnrollmentOptions`
    # containing the text `Mandatory`, not a JSON policy key. Setting this
    # false just removes a key Chrome rejects here — nothing is lost, since
    # it never did anything on this platform.
    chrome.enrollmentMandatory = false;

    fleet.enrollSecretFile = "/etc/orbit/enroll-secret";
    fleet.enrollSecretUnits = [ "secrets.service" ];

    # Safe preparation only: this names an externally managed runtime path
    # for nix-daemon; it does not read or materialise credentials.
    developerTools = {
      enable = true;
      credentialFile = "/etc/nix/aws/credentials";
    };
  };

  # The NixOS-level secrets service runs as root, and the default identity
  # `~/.ssh/id_machine` would expand to /root/.ssh/... — point it at the
  # real key explicitly.
  secrets.identity = "/home/surma/.ssh/id_machine";
  secrets.items.fleet-enroll-secret = {
    target = "/etc/orbit/enroll-secret";
    mode = "0600";
  };

  # TODO(surma): the Chrome CBCM enrolment token.
  #
  # Until this exists, `shopify-chrome-enrollment-token.service` finds no
  # source file, says so, and exits 0 — so the build and the boot are fine,
  # the browser simply is not enrolled.
  #
  # It cannot be added from here: the token has to be encrypted with your
  # age key, and it also needs ROTATING first — the previous value was
  # committed to the shopify-framework repository as an option default and
  # was rendered into a world-readable /nix/store path on this machine, so
  # treat it as disclosed.
  #
  # Once you have a fresh token from the CBCM admin console:
  #
  #   printf %s '<new-token>' \
  #     | nix run nixpkgs#age -- --encrypt \
  #         -r "$(cat secrets/config.nix | grep -A0 'surma =' ...)" ... \
  #     > secrets/chrome-enrollment-token.age
  #
  # (in practice: use the same recipe as the other entries in
  # secrets/config.nix, recipients `surma` and `archon`), add
  #
  #   chrome-enrollment-token = {
  #     contents = ../secrets/chrome-enrollment-token.age;
  #     keys = [ "surma" "archon" ];
  #   };
  #
  # to `secrets.secrets` in secrets/config.nix, and uncomment:
  #
  # secrets.items.chrome-enrollment-token = {
  #   target = "/run/shopify-framework/chrome-enrollment-token";
  #   mode = "0600";
  # };
  allowedUnfreeApps = [
    "1password"
    "1password-cli"
    "cloudflare-warp"
    "google-chrome"
    "slack"
    "endpoint-verification"
  ];
  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    keyd
    hyprlock
    tailscale
    pavucontrol
    hyprsunset
    pciutils
    usbutils
  ];

  services.tailscale.enable = true;

  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "surma" ];
  programs.obs-studio.enable = true;

  # Firefox picks the first capture-capable V4L2 device. Reserve video0 for
  # OBS Cam: it is hidden while inactive (exclusive_caps) and becomes the
  # default camera while OBS is streaming to it.
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=0 card_label="OBS Cam" exclusive_caps=1
  '';

  programs.firefox.enable = true;
  programs.signal.enable = true;

  security.polkit.enable = true;
  security.pam.services.hyprlock = {
    fprintAuth = false;
  };

  users.users.surma = {
    isNormalUser = true;
    description = "Surma";
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "video"
      "audio"
      "seat"
      "uinput"
    ];
    shell = pkgs.zsh;
  };

  home-manager.users.surma = import ./home.nix;

  services.fprintd.enable = true;
  services.udisks2.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?
}
