# Minerva / Fleet TPM+NSS support for archon.
#
# Shopify's Minerva device-identity flow pushes a script through Fleet (orbit)
# that installs and then verifies a set of TPM/PKCS#11 and NSS dependencies.
# Upstream targets Debian/Arch/Fedora and will not support NixOS, so this
# module makes the *declarative* side true (the tools genuinely exist, the TPM
# is genuinely reachable) and supplies a verifying `apt-get` shim to get the
# worker past its package-manager gate without ever asserting anything false.
#
# See SHOPIFY.md ("Minerva TPM/NSS dependencies") for the rationale, the
# manual-run procedure and the rollback.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  minervaAptShim = pkgs.callPackage ./minerva-apt-shim.nix { };
  minervaAutorun = pkgs.callPackage ./minerva-autorun.nix { };

  # `inputs.shopify-framework.nixosModules.chrome-enrollment` (READ ONLY,
  # vendored from Shopify's upstream module — see
  # /home/surma/src/github.com/shopify-playground/shopify-framework/modules/chrome-enrollment.nix)
  # hardcodes the list of Minerva CA issuer CNs it builds
  # `AutoSelectCertificateForUrls` from, and exposes no option to extend it.
  # Shopify rotated the Minerva subordinate CA on 2026-06-12, issuing certs
  # with `CN=Shopify Minerva Subordinate CA 2026`. Upstream still only knows
  # about the two older CNs below, so Chrome silently never offers the new
  # cert for auto-selection: the cert is present and installed, but the
  # policy list that would make Chrome pick it never matches its issuer.
  #
  # Symptom: cert is present in Chrome/NSS but never offered, device shows as
  # untrusted / "Unauthenticated Device" despite Minerva having issued a
  # valid cert. See SHOPIFY.md ("Stale Minerva CA issuer list in
  # chrome-enrollment") for the diagnosis and check.
  #
  # This whole override should be deleted once upstream's module lists the
  # 2026 CA itself (report it to Shopify — their module is stale for every
  # consumer, not just NixOS). Until then: when Shopify rotates the Minerva
  # CA again, add the new issuer CN to this list and rebuild.
  minervaIssuers = [
    "Shopify Minerva Subordinate CA"
    "Shopify Minerva Subordinate CA2"
    # Added after the 2026-06-12 CA rotation.
    "Shopify Minerva Subordinate CA 2026"
  ];

  shopifyDomains = [
    "[*.]shopifycloud.com"
    "[*.]shopify.io"
    "[*.]shopify.com"
  ];

  # Reproduces upstream's certSelectors shape exactly (one JSON entry per
  # domain x issuer), just with the corrected issuer list above.
  minervaCertSelectors = lib.concatMap (
    domain:
    map (
      issuer:
      builtins.toJSON {
        pattern = domain;
        filter = {
          ISSUER = {
            CN = issuer;
          };
        };
      }
    ) minervaIssuers
  ) shopifyDomains;

  workerScript = "/var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh";

  # Everything the Minerva worker (and any other Fleet-pushed script) needs to
  # be able to find. Orbit runs pushed scripts with `env == nil`, so children
  # inherit orbit's systemd environment verbatim — this list *is* the PATH
  # those scripts get.
  orbitScriptPath = [
    # The worker's shebang is `#!/usr/bin/env bash`; without bash here it
    # dies with exit 127 before executing a single line.
    pkgs.bash
    pkgs.coreutils # sha256sum, base64, install, date, ...
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.systemd
    pkgs.util-linux
    pkgs.curl
    pkgs.jq
    pkgs.openssl
    pkgs.gnupg
    pkgs.nss.tools # certutil, modutil
    pkgs.shadow # usermod
    (lib.getBin config.security.tpm2.pkcs11.package) # tpm2_ptool
    (lib.getOutput "getent" pkgs.glibc) # getent (NOT glibc.bin)
    minervaAptShim # apt-get / apt — verifying shim, see minerva-apt-shim.sh
  ]
  ++ [
    # sudo only works from the setuid wrapper dir; pkgs.sudo is not setuid and
    # is useless here.
    "/run/wrappers"
  ];
in
{
  ####################################################################
  # 1. TPM access
  ####################################################################
  security.tpm2 = {
    enable = true;
    # Puts tpm2_ptool in the system profile and
    # /run/current-system/sw/lib/libtpm2_pkcs11.so on disk.
    pkcs11.enable = true;
    # Exports TPM2TOOLS_TCTI / TPM2_PKCS11_TCTI=device:/dev/tpmrm0 so the
    # tools talk to the kernel resource manager rather than guessing.
    tctiEnvironment.enable = true;
    # Creates the `tss` group and the udev rules that give it /dev/tpmrm0.
    applyUdevRules = true;
  };

  # Chrome runs as `surma` and has to be able to open the PKCS#11 token, so
  # the desktop user needs the tss group.
  #
  # This is declared here on purpose: the Minerva/Fleet scripts do this with
  # `usermod -aG tss <user>`, and on NixOS any such imperative group edit is
  # silently reverted by the next `nixos-rebuild switch`. Declaring it makes
  # it survive.
  users.users.surma.extraGroups = [ "tss" ];

  ####################################################################
  # 2. The tools the worker verifies
  ####################################################################
  # Note the split: these are genuinely useful system-wide, so they go in the
  # system profile. The apt-get shim deliberately does NOT — it is only ever
  # visible to orbit's children (and to a manual run that opts in), so the
  # interactive shell and the rest of the host are unaffected by it.
  environment.systemPackages = [
    pkgs.nss.tools
    pkgs.jq
    pkgs.openssl
    pkgs.gnupg
    pkgs.curl
  ];

  ####################################################################
  # 2.5. Work around upstream's stale Minerva CA issuer list
  ####################################################################
  # See the `minervaIssuers` comment above for the full rationale. Upstream's
  # `chrome-enrollment` module already sets this option, so `mkForce` is
  # required to win the merge.
  programs.chromium.extraOpts."AutoSelectCertificateForUrls" = lib.mkForce minervaCertSelectors;

  ####################################################################
  # 3. FHS shims the upstream scripts hardcode
  ####################################################################
  systemd.tmpfiles.rules = [
    # `#!/usr/bin/env bash` needs bash on PATH (handled above); other Fleet
    # scripts use `#!/bin/bash` directly, which needs this.
    "L+ /bin/bash - - - - ${lib.getExe pkgs.bash}"

    # /usr/lib must be a REAL directory, not a symlink: the worker looks for
    # the PKCS#11 module with `find /usr/lib -name 'libtpm2_pkcs11.so*'`, and
    # find does not descend into a symlinked start directory (verified: it
    # silently returns nothing, exit 0). A symlinked /usr/lib would therefore
    # make the check fail while looking like it should pass.
    "d /usr/lib 0755 root root -"
    "L+ /usr/lib/libtpm2_pkcs11.so - - - - /run/current-system/sw/lib/libtpm2_pkcs11.so"

    # /usr/lib64 must ALSO exist, even though nothing is ever placed in it,
    # because of a false-negative bug in Minerva's *installer* script (not
    # the dependency worker, which does this correctly). The installer runs
    # (under `set -o pipefail`):
    #   find /usr/lib /usr/lib64 -name 'libtpm2_pkcs11.so*' 2>/dev/null | grep -q .
    # `find` with multiple start points still exits 1 if ANY of them is
    # missing, even though it already printed the match it found in
    # /usr/lib. `grep -q` sees that match and exits 0, but pipefail makes
    # the pipeline's status the *last non-zero* exit code in the pipe (1),
    # so the subsequent `!` inverts a 1 into "library not found" while the
    # library is right there. Verified live: this deterministically aborted
    # every Fleet attempt. An empty real directory (not a symlink, to avoid
    # any risk of double-counting in the script's later
    # `sort -V | tail -n1` module-version selection) is enough to satisfy
    # `find` and make the check pass. Do NOT remove this as "pointless" —
    # see SHOPIFY.md for the full writeup and the upstream report.
    "d /usr/lib64 0755 root root -"

    # `/usr/local` is untouched by NixOS itself (FHS reserves it for local
    # administration, and the Nix store is where NixOS puts everything it
    # manages instead), so on this host it simply did not exist: `/usr`
    # contained only `bin` and `lib`. Shopify's Minerva/ACME device-trust
    # agent is delivered by Fleet as an installer that (per the leading
    # hypothesis for its exit-1 failure) expects to place the binary at
    # `/usr/local/bin/minerva-agent` — a bog-standard FHS assumption that
    # simply has nowhere to land here. These two rules create *real*
    # directories (not symlinks) at that path so the installer's `mkdir -p`
    # / `install` succeeds, without NixOS claiming any ownership over what
    # gets written inside — this is genuinely third-party, locally-installed
    # software, exactly what `/usr/local` is for.
    "d /usr/local 0755 root root -"
    "d /usr/local/bin 0755 root root -"
  ];

  ####################################################################
  # 4. Orbit's PATH — inherited verbatim by every Fleet-pushed script
  ####################################################################
  systemd.services.orbit.path = orbitScriptPath;

  # The exact same PATH string, written out so a manual run can reproduce
  # orbit's environment byte-for-byte instead of approximating it:
  #
  #   sudo env -i PATH="$(cat /etc/minerva-nixos/script-path)" \
  #     /var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh
  #
  # This lives under /etc/minerva-nixos, NOT /etc/minerva: the real Minerva
  # agent (once installed at /usr/local/bin/minerva-agent, see the tmpfiles
  # rules above) is expected to write its own certificate to
  # /etc/minerva/certificate.pem and almost certainly wants to own that
  # directory outright. NixOS materialising unrelated files (or symlinks)
  # into a directory a third-party agent manages is exactly the kind of
  # half-ownership that causes hard-to-diagnose collisions later, so our own
  # debugging artifacts get a directory we unambiguously own instead.
  environment.etc."minerva-nixos/script-path".text = config.systemd.services.orbit.environment.PATH;

  environment.etc."minerva-nixos/README".text = ''
    This directory is generated by machines/archon/minerva.nix in
    surma's nixenv repo. Nothing here is secret.

    It is deliberately NOT /etc/minerva: that path belongs to Shopify's
    Minerva agent (/usr/local/bin/minerva-agent once Fleet installs it),
    which writes its own certificate.pem there. Keeping our own debugging
    artifacts in a separate, NixOS-owned directory avoids fighting the agent
    for ownership of /etc/minerva.

    script-path
        The PATH that orbit(8) gives to the scripts Fleet pushes to this
        machine. Use it to reproduce that environment for a manual run.

    The `apt-get` on that PATH is NOT a package manager. It is a verifying
    shim (machines/archon/minerva-apt-shim.sh) that installs nothing and
    exits 0 only if the requested packages are genuinely already present.
    Every invocation is logged to /var/log/minerva-apt-shim.log and syslog
    under the tag `minerva-apt-shim`.
  '';

  ####################################################################
  # 5. Automatic execution of the Fleet-dropped worker
  ####################################################################
  # Fleet's parent script drops the worker and then fails to create the unit
  # that would run it (it writes to /etc/systemd/system, which is a read-only
  # store symlink here). This pair does that job instead, so a freshly
  # installed archon needs no human step after enrolment.
  systemd.paths.minerva-tpm-nss-deps = {
    description = "Watch for the Fleet-dropped Minerva TPM/NSS dependency worker";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      # Fires when the worker appears, and also if it already exists at boot.
      PathExists = workerScript;
      # Fires if Fleet rewrites it in place (PathExists alone cannot see a
      # content change, because there is no existence transition).
      PathChanged = workerScript;
      Unit = "minerva-tpm-nss-deps.service";

      # Last-resort ceiling. systemd defaults this to 200 activations per 2s;
      # tightening it makes the intent explicit and bounds the pathological
      # case hard: if this unit ever did start spinning, systemd puts the
      # *path* unit into failure mode and stops watching entirely, rather than
      # letting it churn. Unreachable given the guards on the service side —
      # this exists so that "cannot spin" is enforced, not merely argued.
      TriggerLimitIntervalSec = "1min";
      TriggerLimitBurst = 10;
    };
  };

  systemd.services.minerva-tpm-nss-deps = {
    description = "Run the Minerva TPM/NSS dependency worker (verify-only on NixOS)";

    # /usr/lib/libtpm2_pkcs11.so and /bin/bash come from tmpfiles; without
    # this ordering a boot-time trigger could run before they exist.
    after = [ "systemd-tmpfiles-setup.service" ];
    wants = [ "systemd-tmpfiles-setup.service" ];

    # Cheap belt-and-braces: if the worker vanished between the path event and
    # the start job, skip without counting as a failure.
    unitConfig.ConditionPathExists = workerScript;

    # A failing oneshot leaves the unit in `failed`, which re-arms the path
    # unit, which re-triggers... Bound that explicitly: at most 3 attempts per
    # hour, after which systemd refuses to start it and it stays visibly
    # failed instead of hammering.
    startLimitIntervalSec = 3600;
    startLimitBurst = 3;

    # Exactly the PATH orbit gives its children, so the worker (and the
    # apt-get shim it invokes) sees the same environment either way.
    path = orbitScriptPath;

    environment.HOME = "/root";

    serviceConfig = {
      Type = "oneshot";
      # Required, not cosmetic: a `.path` unit re-arms when its triggered unit
      # goes inactive, and PathExists would still be true, so a plain oneshot
      # would loop forever. Staying `active (exited)` keeps the path unit
      # disarmed. The cost is that a re-run needs an explicit
      # `systemctl restart minerva-tpm-nss-deps.service`.
      RemainAfterExit = true;
      ExecStart = lib.getExe minervaAutorun;
      StateDirectory = "minerva-autorun";
      StateDirectoryMode = "0700";
    };
  };

  # Forward-compatible ordering: once the Fleet enroll secret is delivered by
  # the repo's age-secret mechanism (see SHOPIFY.md, "Fresh install"), orbit
  # must not start before it has been decrypted. Harmless no-op until then.
  systemd.services.orbit.after = lib.optionals (config.secrets.items ? fleet-enroll-secret) [
    "secrets.service"
  ];

  # Make the shim and the runner easy to build and test in isolation:
  #   nix build .#nixosConfigurations.archon.config.system.build.minervaAptShim
  system.build.minervaAptShim = minervaAptShim;
  system.build.minervaAutorun = minervaAutorun;
}
