# Shopify Work Configuration (archon)

Operational notes for the Shopify NixOS tooling on `archon`. This is not a
plan document like `VPN.md` — it's the "how do I redo/repair this" reference,
written after the fact from what actually worked.

## Architecture

The Shopify NixOS modules are consumed as a flake input:

```nix
shopify-framework.url = "git+ssh://containeruser@gitea.surma.technology:2222/surma/shopify-framework.git?ref=main";
```

This points at a **personal Gitea mirror**, not the corp repo. That's
deliberate: the corp repo requires corporate access, but the module you'd use
to *get* corporate access (Fleet enrollment, WARP, etc.) lives in that same
repo — a bootstrap cycle. Fetching from a personal mirror with a personal SSH
key breaks the cycle: the flake input only ever needs the Gitea key, never
corp credentials.

Refreshing the mirror's content from upstream is a **separate, manual,
deliberately unscripted step** that does require corp access. It's done in a
plain clone of the mirror (push whatever changed upstream to the mirror's
`main`), not via anything in this repo. See the mirror's own README for the
corp-side URLs — they're intentionally not reproduced here.

### What `machines/archon/default.nix` imports

```nix
inputs.shopify-framework.nixosModules.warp
inputs.shopify-framework.nixosModules.chrome-enrollment
inputs.shopify-framework.nixosModules.nix-ld
inputs.shopify-framework.nixosModules.fleet
inputs.shopify-framework.nixosModules.packages
inputs.shopify-framework.nixosModules.dev-nginx
```

Plus `shopify.user = "surma";` and unfree entries for `cloudflare-warp`,
`google-chrome`, `slack` in `allowedUnfreeApps`.

### What is deliberately NOT imported

- **`shopify-cache`** — upstream `modules/shopify-cache.nix` reads
  `../scripts/git-credential-shopify`, a file that doesn't exist in any
  commit of the mirror. Importing it fails Nix evaluation outright. It would
  also need corp cache credentials we don't have wired up. Revisit once
  upstream fixes the missing file.
- **`nixosModules.options`** — do not import this alongside the feature
  modules above. Each feature module already path-imports its own
  `./options.nix` internally. The flake attribute `nixosModules.options` is a
  *different Nix value identity* for the same option declarations, so
  importing both gives you a duplicate "option already declared" eval error.
- **The local `modules/nixos/shopify-cloudflare-warp` module** — superseded
  by upstream's `warp.nix`, which also writes the WARP MDM config (the local
  module never did). Not imported by archon anymore; kept in-repo but unused.

## Updating

| Task | Command | Needs corp access? |
|---|---|---|
| Bump the pinned mirror commit | `nix flake update shopify-framework` | No — personal Gitea key only |
| Pull new upstream content into the mirror | manual, in a separate clone of the mirror | Yes |

## Rebuild gotcha: SSH agent mismatch under `sudo`

`~/.ssh/config` pins the Gitea host to a per-session agent socket:

```
IdentityAgent /run/user/%i/ssh-agent
IdentitiesOnly yes
```

That agent is frequently empty; the real key lives in the forwarded/1Password
agent (`$SSH_AUTH_SOCK`). Flake input fetching happens in the *invoking
user's* process, so a plain `sudo nixos-rebuild switch` fetches the
`shopify-framework` input as **root**, which doesn't have your agent and
fails to auth to Gitea.

Two workarounds that work:

```sh
# 1. Force root to use your agent socket
sudo GIT_SSH_COMMAND="ssh -o IdentityAgent=$SSH_AUTH_SOCK" nixos-rebuild switch --flake .#archon

# 2. Build unprivileged (as yourself, with your normal agent), then switch as root
nixos-rebuild build --flake .#archon
sudo ./result/bin/switch-to-configuration switch
```

## Fleet enrollment

This is the fiddly part. The module declares `orbit.service` and it starts
at boot; until provisioned it **restart-loops once per second** with:

```
read enroll secret file: open /etc/orbit/enroll-secret: no such file or directory
```

That's expected — not broken. Two artefacts are missing at that point:

1. The orbit binary: `/opt/orbit/bin/orbit/linux/stable/orbit`
2. The enroll secret: `/etc/orbit/enroll-secret` (mode `0600`, owned `root:root`)

### The kickstart script is useless on NixOS — don't bother

The dev-setup portal offers a `curl | bash` one-liner. It does nothing here:
the bundled `setup.pyz` detects `ID=nixos` in `/etc/os-release` and returns
early ("automatic Linux workstation setup is not yet supported"); even before
that, the shell wrapper fails because `python3`/`apt-get`/`dnf`/`pacman`
aren't on `PATH`. It's not dangerous, just a no-op — don't spend time
debugging it.

### Manual enrollment procedure

1. Get the `.deb` the portal would have installed (`fleet-osquery...deb`).
   Find the download link via the dev-setup portal — see the mirror's README
   for that URL, not reproduced here.

2. Extract it by hand instead of letting `dpkg` run maintainer scripts as
   root — the package is unsigned and fetched without checksum verification.
   `ar`, `dpkg-deb`, `unzip`, `python3` are not on `PATH` by default:

   ```sh
   nix shell nixpkgs#dpkg -c dpkg-deb -x fleet-osquery_*.deb ./extracted
   ```

3. The enroll secret ships *inside* the package, at
   `extracted/etc/default/orbit`, as a line like `ORBIT_ENROLL_SECRET=...`.
   Pull that value out.

4. **Do not** put the secret in `/etc/default/orbit`. The `fleet` module
   declares that path via `environment.etc`, so `nixos-rebuild switch`
   regenerates it (and drops the secret) on every rebuild. The module passes
   `--enroll-secret-path=/etc/orbit/enroll-secret` to orbit, so that's the
   only place the secret should live:

   ```sh
   sudo install -d -m 0755 -o root -g root /etc/orbit
   sudo install -m 0600 -o root -g root /dev/null /etc/orbit/enroll-secret
   printf '%s' "$THE_SECRET_VALUE" | sudo tee /etc/orbit/enroll-secret >/dev/null
   sudo chmod 0600 /etc/orbit/enroll-secret
   ```

   (`printf '%s'`, no trailing newline — some agents are picky about
   whitespace in the secret file.)

5. Copy the orbit binary out of the extracted package to
   `/opt/orbit/bin/orbit/linux/stable/orbit` (matching the path/layout the
   module's systemd unit expects).

6. **Ignore** `extracted/usr/lib/systemd/system/orbit.service` from the
   `.deb` — do not install it. The module's own unit under
   `/etc/systemd/system` (managed by NixOS) is authoritative; installing the
   Debian one creates a competing definition.

7. Restart orbit and check it stopped restart-looping:

   ```sh
   sudo systemctl restart orbit
   systemctl is-active orbit
   systemctl show orbit -p NRestarts --value   # should stay 0
   ```

### Do not run upstream's `fleet-enrolment.sh`

The mirror's own convenience script is a bad idea to run as-is on this
machine: it rewrites `/etc/nixos`, runs `nixos-rebuild switch` itself, copies
a payload over `/`, and executes the Debian package's `postinst` as root
while ignoring failures. The manual procedure above is the safe path.

### Verifying enrollment actually worked

Being "not restart-looping" is necessary but not sufficient — proof of
enrollment is two-way traffic with Fleet:

```sh
systemctl is-active orbit                       # active
systemctl show orbit -p NRestarts --value        # 0, staying 0
journalctl -u orbit -f                           # watch for:
  # "received notification to run scripts"
  # "getting script"
  # "saving script result"
test -f /opt/orbit/secret-orbit-node-key.txt     # exists only after successful enrollment
```

Also confirm the enroll-secret-missing error is gone and there are no
401/403 responses in the logs.

## Known quirk: scripts fail with exit 127

Fleet-pushed scripts commonly fail on NixOS with **exit code 127** (command
not found) because Fleet's scripts assume FHS paths (`/usr/bin/...` etc.)
that don't exist on NixOS. Enrollment and telemetry reporting still work
fine — only script execution is affected. This means MDM compliance checks
that run as Fleet scripts can silently no-op, so the host may show as
non-compliant in Fleet's dashboard even though the agent itself is healthy.
Don't chase this as a broken-enrollment symptom.

## After enrollment

Order of operations, each with its own async delay:

1. **Minerva cert** arrives asynchronously via WARP/Fleet. Chrome needs a
   *full quit and relaunch* (not just closing the window — Chrome keeps
   background processes alive) to pick it up, otherwise you get
   "Unauthenticated Device".
2. Okta.
3. Corp cache credentials.
4. The `shopify-cache` module, once upstream fixes the missing
   `git-credential-shopify` script (see Architecture above).
5. tec/dev tooling.

`shopify-setup-status` (provided by the `packages` module) gives a running
overview of where things stand.

Two side effects worth knowing about, both from imported modules:

- `dev-nginx` lowers `net.ipv4.ip_unprivileged_port_start` to 80
  **system-wide**, and runs an nginx instance as your user.
- `orbit` runs as root with `--enable-scripts`, meaning Fleet can execute
  arbitrary scripts as root on this machine. That's the whole point of MDM,
  but worth remembering when reasoning about the trust boundary.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `orbit` restart-looping, "no such file or directory" for enroll-secret | Not enrolled yet | Follow manual enrollment procedure above |
| `nixos-rebuild switch` fails to fetch `shopify-framework` under `sudo` | Root has no SSH agent for Gitea | Use `GIT_SSH_COMMAND` workaround or build-then-switch |
| Eval error "option already declared" | Both a feature module and `nixosModules.options` imported | Remove the `nixosModules.options` import |
| Eval error about `../scripts/git-credential-shopify` missing | `shopify-cache` module imported | Don't import it until upstream fixes the path |
| Fleet script runs return exit 127 | FHS path assumptions on NixOS | Expected, harmless to enrollment; ignore unless it's the actual task at hand |
| Chrome says "Unauthenticated Device" | Minerva cert not picked up yet | Fully quit and relaunch Chrome, not just close the window |
| Secret written to `/etc/default/orbit` disappears | That path is regenerated by `environment.etc` on every rebuild | Only ever write the secret to `/etc/orbit/enroll-secret` |
| Minerva installer reports the PKCS#11 library missing while `find` can clearly see it | Installer's `find \| grep -q` check under `pipefail` false-negatives when `/usr/lib64` doesn't exist (see below) | `systemd.tmpfiles.rules` creates an empty real `/usr/lib64` on this host |

### Named gotcha: the installer's `find`+`pipefail` false negative

This is a **distinct bug from the `/usr/lib` symlink issue above**, in a
different script (Minerva's top-level *installer*, not the
`install-tpm-nss-deps-worker.sh` dependency worker), and it is the one that
was actually causing the three failed Fleet enrollment attempts on this
host.

The installer runs under `set -o pipefail` (line 15) and then checks for the
PKCS#11 module with:

```sh
find /usr/lib /usr/lib64 -name 'libtpm2_pkcs11.so*' 2>/dev/null | grep -q .
```

Reproduced live on this host, where `/usr/lib64` does not exist:

- `find` is given two start points. It happily finds and **prints** the
  match under `/usr/lib` — but because one of its start points
  (`/usr/lib64`) doesn't exist, `find` still exits **1** overall.
- `grep -q .` sees that printed match on stdin and exits **0**.
- Under `pipefail`, the pipeline's exit status is the last *non-zero* exit
  code among the stages, not simply the last stage's — so the pipeline as a
  whole reports **1**, even though `grep` succeeded.
- The script then does the equivalent of `if ! <that pipeline>; then
  conclude "library missing"; fi` — inverting a 1 into "not found" while
  looking straight at the file.

This is subtle because it depends on the *combination* of `find`'s
multi-start-point exit semantics with `pipefail`'s last-non-zero-wins
semantics; neither half is surprising in isolation, and the failure mode
(false negative, not a crash) gives no error message to search for.

For contrast: `install-tpm-nss-deps-worker.sh` (the dependency worker
delivered separately) checks for the same library correctly, by guarding
each directory with `[[ -d ]]` and running `find` one directory at a time —
so it never hits this bug on identical filesystem state. The installer and
the worker are two different pieces of code with two different (and
non-equivalent) implementations of "does this library exist" checks.

**Worth reporting upstream.** The installer's check is broken on *any*
distro/host lacking `/usr/lib64` (not just NixOS), and Shopify's own
dependency worker already contains the correct `[[ -d ]]`-guarded
per-directory loop right next to it — so this is a one-line fix on their
side (either guard each `find` start point the same way, or drop `pipefail`
reliance on this line) that would remove the need for the `/usr/lib64` shim
here entirely.

## Open items

- ~~The Fleet enroll secret is currently manual, undeclared state~~ — **done**.
  It is now delivered declaratively via this repo's age-encrypted secrets
  mechanism: `secrets/fleet-enroll-secret.age`, registered in
  `secrets/config.nix`, and materialised to `/etc/orbit/enroll-secret`
  (mode `0600`) by `secrets.items.fleet-enroll-secret` in
  `machines/archon/default.nix`. See "Delivering the enroll secret
  declaratively" below for how it works and how to rotate it. A fresh
  install of archon no longer needs the manual extraction-from-.deb step for
  this artefact — only restoring `~/.ssh/id_machine` (see "The age identity
  is the real bootstrap dependency" below).
- Upstream issues worth raising against `shopify-framework` (i.e. against
  the corp repo, via whoever refreshes the mirror):
  - Missing `scripts/git-credential-shopify` breaks `shopify-cache` eval.
  - `nixosModules.options` vs. per-module `./options.nix` path-imports is a
    landmine for anyone who imports both.
  - The Chrome enrollment token appears to be hardcoded in the module rather
    than configurable/secret-injected.
  - `fleet-enrolment.sh`'s blast radius (rewrites `/etc/nixos`, runs
    `nixos-rebuild switch`, copies a payload over `/`, runs `postinst` as
    root ignoring failures) should probably be scoped down.
  - The Minerva installer's `find /usr/lib /usr/lib64 -name
    'libtpm2_pkcs11.so*' | grep -q .` check under `pipefail` (see "Named
    gotcha" above) false-negatives on any host without `/usr/lib64`. Their
    own dependency worker already contains the correct `[[ -d ]]`-guarded
    per-directory loop — porting that same pattern to the installer is a
    one-line fix.

## Minerva TPM/NSS dependencies (`machines/archon/minerva.nix`)

Minerva (the device-identity piece behind the Chrome "Unauthenticated
Device" wall) needs a TPM-backed PKCS#11 token. Fleet pushes a script that
drops a worker at
`/var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh` and is supposed
to run it from a systemd unit. Two things go wrong on NixOS:

1. The parent script tries to write
   `/etc/systemd/system/minerva-tpm-nss-deps-install.service`. On NixOS
   `/etc/systemd/system` is a symlink into a read-only store path, so the
   unit is never created and the worker never runs. (No log, no unit, no
   status file — that's why there's nothing to look at from earlier
   attempts.)
2. Even run by hand the worker dies immediately. Its shebang is
   `#!/usr/bin/env bash` and orbit's PATH contains no bash → exit 127. Get
   past that and it hits
   `fail "unable to find apt-get, pacman, dnf, or yum"` — which fires
   *before* its own dependency verification, so the fact that every
   dependency could be present doesn't help.

`machines/archon/minerva.nix` fixes all of that declaratively.

### What the module does

- **`security.tpm2`** with `pkcs11.enable`, `tctiEnvironment.enable`,
  `applyUdevRules`. This creates the `tss` group, the udev rules that give it
  `/dev/tpmrm0`, puts `tpm2_ptool` in the system profile and
  `libtpm2_pkcs11.so` at `/run/current-system/sw/lib/`.
- **`users.users.surma.extraGroups = [ "tss" ]`** — Chrome runs as `surma`
  and has to open the token. See the warning below.
- **System packages** for what was genuinely missing: `nss.tools`
  (certutil/modutil), `jq`, `openssl`, `gnupg`, `curl`.
- **`systemd.tmpfiles` rules** for `/bin/bash` and for `/usr/lib` +
  `/usr/lib/libtpm2_pkcs11.so`. `/usr/lib` is created as a **real directory**,
  not a symlink, on purpose: the worker looks for the module with
  `find /usr/lib -name 'libtpm2_pkcs11.so*'`, and `find` does not descend
  into a symlinked start directory — it silently prints nothing and exits 0.
  A symlinked `/usr/lib` would fail the check while looking like it should
  pass.
- **`systemd.tmpfiles` rule for `/usr/lib64`** (empty real directory). See
  "Named gotcha: the installer's `find`+`pipefail` false negative" below —
  this is a separate bug from the one above, in the *installer* script
  rather than the dependency worker, and it is the one that actually
  deterministically aborted every Fleet attempt.
- **`systemd.services.orbit.path`** — orbit executes pushed scripts with
  `env == nil`, so children inherit orbit's systemd environment verbatim.
  This list therefore *is* the PATH every Fleet-pushed script gets: bash,
  coreutils, findutils, grep, sed, awk, systemd, util-linux, curl, jq,
  openssl, gnupg, nss.tools, shadow (`usermod`), `tpm2-pkcs11` (bin output),
  glibc's `getent` output, `/run/wrappers` (for a *setuid* `sudo` —
  `pkgs.sudo` is not setuid and is useless here), and the apt-get shim.
- Writes the resulting PATH to **`/etc/minerva-nixos/script-path`** so a manual
  run can reproduce orbit's environment byte-for-byte instead of
  approximating it, plus a short `/etc/minerva-nixos/README`. This lives
  under `/etc/minerva-nixos`, not `/etc/minerva`: the real Minerva agent
  (`/usr/local/bin/minerva-agent`, once Fleet's installer can place it — see
  below) is expected to write its own `certificate.pem` under `/etc/minerva`
  and should own that directory outright.
- **`systemd.tmpfiles` rules for `/usr/local` and `/usr/local/bin`**, created
  as real directories. `/usr/local` did not exist at all on this host (`/usr`
  contained only `bin` and `lib`), which is the leading hypothesis for why
  Fleet's ~30s-interval installer script has been failing with exit 1: it
  almost certainly tries to place `/usr/local/bin/minerva-agent` there. This
  is not a NixOS-managed path — FHS reserves `/usr/local` for local
  administration — so creating it is legitimate, not a workaround-lie.

### The `apt-get` shim, and why it isn't a lie

`machines/archon/minerva-apt-shim.sh` (built by `minerva-apt-shim.nix`)
provides `apt-get` and `apt`. It exists solely to get the worker past its
`command -v apt-get` gate.

It is **not** a package manager and it does not pretend to be one. It
installs nothing, downloads nothing, touches no state:

- `apt-get update` → success, and this is the one genuine no-op: there is no
  package index to refresh on NixOS and nothing about the subsequent
  install's outcome depends on it.
- `apt-get install P…` → for each requested Debian package name it looks up
  what that package is expected to *provide* (commands, or a shared library
  discovered exactly the way the caller will look for it) and **checks
  reality**. Exit 0 iff every requested package is genuinely satisfied right
  now; otherwise non-zero listing precisely what is missing.
- **Unknown package name → hard failure.** If we don't know what a package
  is supposed to provide, we can't honestly assert it's there.
- **Unknown option → hard failure.** No guessing at semantics we don't
  implement. Common no-op flags (`-y`, `-qq`, `--no-install-recommends`, …)
  are accepted and ignored.

The honesty property has a structural guarantee, not just good intentions:
the shim is built with `runtimeInputs = [ ]` and its two internal helpers
(`find`, `logger`) are baked in by absolute store path. It therefore sees
*exactly* the PATH its caller sees and cannot accidentally "find" a tool the
calling script won't find. A PASS from the shim means the worker's own
`verify_dependencies()` will also pass, for the same reasons.

Every invocation — full argv, PATH, and verdict — is appended to
`/var/log/minerva-apt-shim.log` and sent to syslog under the tag
`minerva-apt-shim`. There is an audit trail of every assertion it has made.

The shim is deliberately **not** in `environment.systemPackages`. It is
reachable only via orbit's PATH (and an explicit manual run), so an
interactive shell on this machine still has no `apt-get`.

### The worker runs automatically

You should not have to run anything by hand. `minerva.nix` declares a pair of
units that do the job Fleet's parent script fails to do:

- **`minerva-tpm-nss-deps.path`** watches
  `/var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh` with both
  `PathExists=` (fires when Fleet drops it, and at boot if it is already
  there) and `PathChanged=` (fires if Fleet rewrites it in place — a pure
  `PathExists` unit cannot see a content change, because there is no
  existence transition).
- **`minerva-tpm-nss-deps.service`** runs
  `machines/archon/minerva-autorun.sh` as root with `path =` set to the
  *same* list as orbit's, so the worker sees a byte-identical PATH whether
  Fleet launches it or we do.

So on a fresh machine the sequence is: enrol → Fleet pushes the Minerva parent
script → the parent drops the worker → inotify fires → the worker runs →
`state=success`. No human step.

(Evidence that the parent really does drop the worker before it dies: the
worker file has existed on this machine since 22 Jul, its log was never
created, and the unit never existed. Dropping happens first; unit creation is
what fails.)

#### Why it doesn't loop

This is the trap with `systemd.paths`. A `.path` unit **re-arms whenever its
triggered unit goes inactive**, and then re-evaluates its conditions — so a
plain `Type=oneshot` with `PathExists=` retriggers forever. Two guards:

1. **`RemainAfterExit=true`** — after a successful run the service stays
   `active (exited)`, so the path unit never re-arms. This is load-bearing,
   not cosmetic. The price is that forcing a re-run needs an explicit
   `systemctl restart` (below).
2. **`StartLimitBurst=3` / `StartLimitIntervalSec=3600`** — a *failing* run
   does go inactive, so it would re-arm and loop. The rate limit caps that at
   three attempts an hour, after which systemd refuses to start it and it
   sits visibly `failed` instead of hammering the machine.

On top of that the script itself is idempotent: it records the sha256 of the
worker that last succeeded in `/var/lib/minerva-autorun/last-success.sha256`,
and exits 0 immediately if that hash still matches *and* the status file still
reads `state=success`. Reboots are free. If Fleet ever drops a *different*
worker, the hash differs and it runs again.

#### Fail-safe

The runner never writes the status file. The only thing that can write
`state=success` is the worker, after its own `verify_dependencies()` passed.
The runner double-gates on top: it stamps success only if the worker exited 0
**and** the status file it wrote genuinely says `state=success`. A worker that
exits 0 with a non-success status is treated as a failure. Everything —
verdict, the worker's log, the status file — is echoed into the journal,
because the worker otherwise redirects all its own output into a file.

#### It does not fight Fleet

- The unit is named `minerva-tpm-nss-deps.service`, deliberately *not*
  upstream's `minerva-tpm-nss-deps-install.service`, so if Fleet ever manages
  to create its own unit we do not shadow or conflict with it.
- An `flock` serialises our own triggers against each other. It does **not**
  lock Fleet out — Fleet would not take the lock. That's acceptable: on NixOS
  the worker installs nothing, so two concurrent runs can at worst interleave
  log lines. There is nothing to corrupt.
- Once the status says success, our runner stops running at all.

#### Watching / forcing it

```sh
systemctl status minerva-tpm-nss-deps.path minerva-tpm-nss-deps.service
journalctl -u minerva-tpm-nss-deps.service          # full history, incl. worker log
sudo systemctl restart minerva-tpm-nss-deps.service # force a re-check
sudo rm /var/lib/minerva-autorun/last-success.sha256 # force a full re-run
```

### Running the worker manually (fallback)

Only needed for debugging, or before the units exist.

```sh
# 1. Rebuild and switch first — none of the above exists until you do.
nixos-rebuild build --flake .#archon
sudo ./result/bin/switch-to-configuration switch

# 2. Sanity-check the environment before touching the worker.
cat /etc/minerva-nixos/script-path
sudo env -i PATH="$(cat /etc/minerva-nixos/script-path)" apt-get install -y \
  libtpm2-pkcs11-tools libtpm2-pkcs11-1 libnss3-tools gnupg curl jq \
  coreutils openssl                  # expect: VERDICT=PASS, exit 0

# 3. Run the worker with orbit's exact PATH.
sudo env -i \
  PATH="$(cat /etc/minerva-nixos/script-path)" \
  HOME=/root \
  bash /var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh

# 4. Inspect the results.
cat /var/lib/fleet/minerva-agent/pkcs11-deps-install.status   # want state=success
cat /var/log/minerva-tpm-nss-deps-install.log
cat /var/log/minerva-apt-shim.log
journalctl -t minerva-apt-shim
```

The worker redirects all its own output to
`/var/log/minerva-tpm-nss-deps-install.log`, so the terminal will look silent.
`state=failed` in the status file names the stage that failed.

### Rolling back

Nothing here is destructive — the worker writes only its own status file and
log, and the shim writes only its log — but:

```sh
# revert the config
sudo nixos-rebuild switch --rollback          # or pick an older boot generation

# remove the worker's artefacts
sudo rm -f /var/lib/fleet/minerva-agent/pkcs11-deps-install.status \
           /var/log/minerva-tpm-nss-deps-install.log \
           /var/log/minerva-apt-shim.log

# the FHS shims are tmpfiles-managed; after rolling back the config they are
# not recreated, but the existing ones must be removed by hand
sudo rm -f /bin/bash /usr/lib/libtpm2_pkcs11.so && sudo rmdir /usr/lib
```

Reverting the module removes `surma` from `tss` on the next switch, which
Chrome will notice (log out/in for the group change to take effect either
way).

### Group membership added by Fleet scripts does not survive

Minerva's own scripts do `usermod -aG tss <user>`. On NixOS
`users.users.*.extraGroups` is authoritative: any imperative `usermod`,
`groupadd` or `gpasswd` change is silently reverted by the next
`nixos-rebuild switch`. That's why the `tss` membership is declared in
`minerva.nix`. If a future Minerva stage adds the user to some *other* group,
it will work until the next rebuild and then quietly stop working — add it to
`minerva.nix` instead of re-running the script.

### What this does not achieve

It satisfies the dependency gate, and only that. It gets the worker to
`state=success`. It does **not** initialise a PKCS#11 token, does not enrol a
key with Minerva, and does not obtain a device certificate. There are
presumably further Minerva stages, pushed as further Fleet scripts, that we
can't see from here — those may well hit their own NixOS assumptions
(FHS paths, `systemctl enable` of units written to `/etc/systemd/system`,
`apt-get` sub-commands the shim deliberately refuses, …). Expect to iterate.

## Fresh install of archon from scratch

Everything above assumes a machine that is already enrolled. This is the
reformat story: what a bare NixOS install needs before Shopify tooling works,
and honestly which parts a machine can do for itself.

Legend: **[nix]** = automatic once the flake is applied. **[manual]** = a human
must do it, with the reason why.

| # | Step | |
|---|---|---|
| 1 | Install NixOS, clone this repo, `nixos-rebuild switch --flake .#archon` | **[manual]** — it's the bootstrap |
| 2 | Restore `~/.ssh/id_machine` (the age identity) | **[manual]** — root of trust, see below |
| 3 | WARP installed & MDM-configured | **[nix]** (`warp.nix`) |
| 4 | WARP *registration* | **[manual]** — browser SSO |
| 5 | Obtain the `fleet-osquery_*.deb` | **[manual]** — per-user tokenised URL behind corp SSO |
| 6 | Orbit binary at `/opt/orbit/bin/orbit/linux/stable/orbit` | **[manual today]**, could be **[nix]** — see below |
| 7 | `/etc/orbit/enroll-secret` | **[nix]** — age secret, see below |
| 8 | `orbit.service` running & enrolled | **[nix]** (`fleet.nix`), once 6 + 7 exist |
| 9 | TPM/PKCS#11 + NSS tooling, FHS shims, orbit PATH | **[nix]** (`minerva.nix`) |
| 10 | Minerva dependency worker runs to `state=success` | **[nix]** (`minerva-tpm-nss-deps.path`) |
| 11 | Chrome enterprise enrollment | **[nix]** token (`chrome-enrollment`), but sign-in is **[manual]** |
| 12 | Okta, corp cache creds, tec/dev tooling | **[manual]** — browser SSO |

Steps 7, 9 and 10 are the ones this repo automates. 6 is the remaining one
that is *worth* automating and currently is not; the rest are genuinely
human.

### The age identity is the real bootstrap dependency

Step 2 is not optional and cannot be automated — it is the root of trust.
Either restore `~/.ssh/id_machine` from 1Password/backup, or run
`nix run .#secrets -- genkey` on the new machine, put the new public key in
`secrets/config.nix` under `archon`, and `nix run .#secrets -- recrypt -m archon`
**from another machine that still holds a recipient key**.

This matters for the section below: moving the enroll secret into the age
mechanism does not eliminate a manual step, it *merges* it into one you
already have. You go from "recover the machine key **and** re-fetch the Fleet
secret out of a .deb" to just "recover the machine key".

### 7. Delivering the enroll secret declaratively (implemented)

`/etc/orbit/enroll-secret` used to be hand-written, undeclared state, lost on
reformat. It is now delivered by the repo's existing age mechanism: on NixOS,
`modules/features/secrets.nix` installs a `secrets.service` (oneshot,
`RemainAfterExit`, `wantedBy = multi-user.target`) that decrypts each
`secrets.items.<name>` to a target path with a mode. The ciphertext lives at
`secrets/fleet-enroll-secret.age`, registered in `secrets/config.nix` for
recipients `surma` and `archon`, and `machines/archon/default.nix` sets:

```nix
# The NixOS-level secrets service runs as root, and the default identity
# `~/.ssh/id_machine` would expand to /root/.ssh/... — point it at the
# real key explicitly.
secrets.identity = "/home/surma/.ssh/id_machine";
secrets.items.fleet-enroll-secret = {
  target = "/etc/orbit/enroll-secret";
  mode = "0600";
};
```

`minerva.nix` adds `After=secrets.service` to `orbit.service`, but only once
`secrets.items.fleet-enroll-secret` actually exists — so orbit does not race
the decryption.

#### Rotating the secret

If Fleet ever reissues the enroll secret, update it like any other secret in
this repo:

1. Get the new value (same source as before: the `ORBIT_ENROLL_SECRET=` line
   inside `extracted/etc/default/orbit` in a fresh Fleet `.deb`, or wherever
   Fleet surfaces it going forward).
2. Edit the encrypted file in place, then re-encrypt for all recipients:

   ```sh
   cd ~/src/github.com/surma/nixenv
   nix run .#secrets -- edit secrets/fleet-enroll-secret.age
   # replace the contents with the new value, no trailing newline, save & quit
   nix run .#secrets -- recrypt fleet-enroll-secret
   ```

3. `nixos-rebuild switch --flake .#archon` (or wait for the next boot) to
   have `secrets.service` write the new value to `/etc/orbit/enroll-secret`.

Caveats, stated plainly:

- The `.age` file is committed to a **public** repo. That is the same posture
  as every other secret in `secrets/`, and age with ed25519 recipients is the
  intended use, but it does mean the ciphertext is world-readable forever.
  This was a deliberate choice for this secret, matching how every other
  secret in this repo is handled — if it is ever considered too sensitive for
  that, revert to the manual procedure and remove the `.age` file and its
  `secrets/config.nix`/`machines/archon/default.nix` entries.
- `secrets.service` decrypts at boot; the file will be recreated on every
  boot, which also means a hand-edit of `/etc/orbit/enroll-secret` would be
  silently reverted. That's the point, but worth knowing.

#### Interaction with the `fleet` module's tmpfiles rule

The upstream `fleet` module already declares `d /etc/orbit 0700 root root -`,
and the secrets helper does its own `mkdir -p` of the target's parent. These
do not conflict, and the ordering happens to be right:

- `systemd-tmpfiles-setup.service` runs at `sysinit.target`, well before
  `secrets.service` (`multi-user.target`). So `/etc/orbit` already exists as
  `0700 root root` by the time the secrets helper runs, and its `mkdir -p`
  is a no-op — `mkdir -p` does not alter the mode of an existing directory,
  so the 0700 is not widened to the umask default.
- Even if that order were ever reversed, tmpfiles `d` adjusts mode and
  ownership on *existing* directories too, so it is self-correcting on the
  next boot.

One genuinely good property worth noting: the helper does
`touch <target>; chmod <mode> <target>` **before** redirecting `age --decrypt`
into it. The file is already `0600` when the plaintext lands, so there is no
window in which the decrypted secret is world-readable.

The one thing to *not* do is add another `d /etc/orbit ...` or an
`environment.etc."orbit/enroll-secret"` entry. `environment.etc` would put the
secret in the world-readable Nix store — which is exactly the mistake the
"do not write the secret to `/etc/default/orbit`" note above is about.

### 6. The orbit binary — assessment and recommendation

Today it is copied by hand out of a `.deb` fetched from a per-user tokenised
URL. Not reproducible. `ORBIT_DISABLE_UPDATES=true` is set, so whatever
binary is placed there stays put — a pin is meaningful and stable.

| Option | Verdict |
|---|---|
| **Fixed-output derivation fetching the portal URL** | **Rejected.** The URL carries a per-user token, is itself a secret, expires, and would land in a public repo. |
| **Vendor the binary into the private Gitea mirror** | Viable, and the *only* option that removes the download entirely. Same trust model as the module mirror (personal key, private repo). Costs: a ~40–80 MB blob in a repo pulled on every `nix flake update`, refreshing it is the same manual corp-access chore as refreshing the module mirror, and re-hosting a vendor binary is a judgement call you should make consciously rather than by default. |
| **`requireFile`** | **Recommended.** Does not remove the download (nothing can — see below), but makes *placement* declarative and hash-pinned. |
| **Document it** | The status quo. Strictly worse than `requireFile` for the same amount of human effort. |

Recommended shape — hash-pinned, no secret URL, fails with a useful message:

```nix
# machines/archon/orbit-binary.nix (NOT implemented; needs the real sha256)
{ pkgs, ... }:
let
  orbitBin = pkgs.requireFile {
    name = "orbit";
    sha256 = "<sha256 of /opt/orbit/bin/orbit/linux/stable/orbit>";
    message = ''
      Extract it from the Fleet .deb (see "Manual enrollment procedure"):
        nix shell nixpkgs#dpkg -c dpkg-deb -x fleet-osquery_*.deb ./extracted
        nix-store --add-fixed sha256 ./extracted/opt/orbit/bin/orbit/linux/stable/orbit
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d /opt/orbit/bin/orbit/linux/stable 0755 root root -"
    "L+ /opt/orbit/bin/orbit/linux/stable/orbit - - - - ${orbitBin}"
  ];
}
```

A store symlink is fine for the binary itself: orbit's mutable state lives
under `--root-dir=/opt/orbit`, not next to the executable, and `nix-ld`
(already wired up by the `fleet` module) handles it being a non-Nix ELF.

Not implemented here because it needs the sha256 of the live binary, and
`/opt/orbit` is off limits for this work — take the hash yourself and drop the
file in.

### What genuinely cannot be automated

Not "hard", not "later" — structurally impossible from a config file:

- **WARP registration.** `warp-cli` needs an interactive browser SSO round
  trip. The *configuration* is declarative (`warp.nix` writes the MDM file);
  the *identity* is not.
- **Downloading the Fleet package.** The dev-setup portal issues a per-user,
  tokenised, expiring URL behind corp SSO. There is no stable URL to pin, and
  the token must not be committed.
- **Anything behind Okta / Google SSO**: Chrome enterprise sign-in, corp cache
  credentials, the tec/dev tooling bootstrap.
- **Refreshing the `shopify-framework` mirror** from the corp repo. Needs corp
  access by design — that's the bootstrap cycle the mirror exists to break.
- **Restoring `~/.ssh/id_machine`.** It is the key that unlocks everything
  else; it cannot be delivered by the thing it unlocks.
- **Minerva issuing a device certificate.** Asynchronous and server-side. All
  this machine can do is be ready for it.

Realistic floor for a reformat, with steps 6 and 7 adopted: install + restore
the age key + register WARP + fetch the `.deb` once (for the orbit binary) +
sign in to Chrome/Okta. Everything else, including the entire Minerva
TPM/NSS dependency stage, is handled by the flake.
