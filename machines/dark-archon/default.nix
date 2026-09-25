{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # NOTE(surma): dark-archon has different hardware than archon. Re-add the
    # matching `inputs.nixos-hardware.nixosModules.<model>` import once the
    # model is known.
    inputs.home-manager.nixosModules.home-manager

    ./hardware.nix

    ../../profiles/nixos/base.nix
    ../../profiles/nixos/gui/desktop.nix
    ../../profiles/nixos/gui/hyprland.nix
    ../../profiles/nixos/platform/laptop.nix
    # NOTE(surma): Framework-specific fixes. Re-add
    # ../../profiles/nixos/platform/framework.nix if this is a Framework laptop.

    # Everything Shopify — WARP, Fleet/orbit, Chrome CBCM, Minerva TPM device
    # trust, Endpoint Verification, the FHS shims and the apt-get shim — now
    # lives in one self-contained module. See machines/archon for the full
    # story.
    inputs.shopify-framework.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 0;
  };

  services.sunshine = {
    enable = true;
    # The NixOS module's generic graphical-session.target also runs in the
    # GDM greeter's user manager. Start Sunshine from the Hyprland-only target
    # in machines/dark-archon/home.nix instead.
    autoStart = false;
    openFirewall = true;
    settings = {
      capture = "wlr";
      origin_web_ui_allowed = "wan";
    };
  };

  networking.hostName = "dark-archon"; # Define your hostname.

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

    developerTools = {
      enable = true;
    };
  };

  # TODO(surma): the Chrome CBCM enrolment token.
  #
  # Until this exists, `shopify-chrome-enrollment-token.service` finds no
  # source file, says so, and exits 0 — so the build and the boot are fine,
  # the browser simply is not enrolled.
  #
  # It cannot be added from here: the token has to be encrypted with your
  # age key. Once you have a fresh token from the CBCM admin console:
  #
  #   printf %s '<new-token>' \
  #     | nix run nixpkgs#age -- --encrypt \
  #         -r "$(cat secrets/config.nix | grep -A0 'surma =' ...)" ... \
  #     > secrets/chrome-enrollment-token.age
  #
  # (in practice: use the same recipe as the other entries in
  # secrets/config.nix, recipients `surma` and `dark-archon`), add
  #
  #   chrome-enrollment-token = {
  #     contents = ../secrets/chrome-enrollment-token.age;
  #     keys = [ "surma" "dark-archon" ];
  #   };
  #
  # to `secrets.secrets` in secrets/config.nix, and uncomment:
  #
  # secrets.items.chrome-enrollment-token = {
  #   target = "/run/shopify-framework/chrome-enrollment-token";
  #   mode = "0600";
  # };
  allowedUnfreeApps = [
    "cloudflare-warp"
    "google-chrome"
    "slack"
    "endpoint-verification"
  ];
  # programs.firefox.enable = lib.mkForce false;
  environment.systemPackages = with pkgs; [
     (pkgs.writeShellScriptBin "x-www-browser" ''exec ${lib.getExe pkgs.google-chrome} "$@"'')
    pciutils
    usbutils
  ];

  programs.obs-studio.enable = true;

  # Firefox picks the first capture-capable V4L2 device. Reserve video0 for
  # OBS Cam: it is hidden while inactive (exclusive_caps) and becomes the
  # default camera while OBS is streaming to it.
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=0 card_label="OBS Cam" exclusive_caps=1
  '';

  programs.signal.enable = true;

  users.users.surma = {
    description = "Surma";

    # nexus runs services.key-poller and SSHes in as surma to read the
    # Shopify key when shopisurm and archon are unreachable. Merges with the
    # `surma` key that profiles/nixos/base.nix already installs.
    openssh.authorizedKeys.keys = with config.secrets.keys; [
      nexus
    ];
  };

  home-manager.users.surma = import ./home.nix;

  system.stateVersion = "26.05"; # Did you read the comment?
}
