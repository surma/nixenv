# shellcheck shell=bash
#
# minerva-autorun — runs Shopify's Minerva TPM/NSS dependency worker exactly
# once, automatically, when Fleet drops it on this machine.
#
# WHY THIS EXISTS
#   Fleet pushes a parent script that (a) writes the worker to
#   /var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh and then
#   (b) tries to create and start a systemd unit for it under
#   /etc/systemd/system. On NixOS (b) is impossible — that directory is a
#   symlink into a read-only store path — so the worker is dropped but never
#   executed. minerva-autorun.path notices the drop and this script does (b)'s
#   job, declaratively, with a PATH that actually contains the worker's
#   dependencies.
#
# WHAT THE WORKER ACTUALLY DOES ON NIXOS
#   Nothing is installed. Every dependency comes from Nix. The worker's only
#   real effects are running its own verify_dependencies() and writing
#   /var/lib/fleet/minerva-agent/pkcs11-deps-install.status plus
#   /var/log/minerva-tpm-nss-deps-install.log. That is why automating it is
#   safe: it is a verification pass, not a mutation.
#
# HONESTY / FAIL-SAFE
#   This script never writes the status file. The only thing that can write
#   state=success is the worker itself, after its own verification passed.
#   We double-gate on top of that: we record a success stamp only if the
#   worker exited 0 AND the status file it wrote genuinely reads
#   state=success. Anything else exits non-zero and is loud in the journal.
#
# IDEMPOTENCE
#   A stamp file records the sha256 of the worker that last succeeded. If the
#   status still says success and the worker's content is unchanged, this is
#   a no-op. If Fleet ever drops a *different* worker, the hash differs and it
#   runs again.
#
readonly WORKER=/var/lib/fleet/minerva-agent/install-tpm-nss-deps-worker.sh
readonly STATUS_FILE=/var/lib/fleet/minerva-agent/pkcs11-deps-install.status
readonly WORKER_LOG=/var/log/minerva-tpm-nss-deps-install.log
readonly STATE_DIR=/var/lib/minerva-autorun
readonly STAMP="$STATE_DIR/last-success.sha256"
readonly LOCK="$STATE_DIR/lock"

# Absolute paths, on purpose: this script must not perturb the PATH it hands
# to the worker. The worker has to see byte-for-byte what orbit would give it,
# otherwise the apt-get shim's assertions would be about a different
# environment than the one Fleet-pushed scripts actually run in.
readonly CU="@coreutils@"
readonly BASH_BIN="@bash@"
readonly FLOCK="@flock@"

say() { printf 'minerva-autorun: %s\n' "$*"; }

# True iff the worker's own status file currently reports success.
status_is_success() {
  local line
  [ -f "$STATUS_FILE" ] || return 1
  while IFS= read -r line; do
    [ "$line" = "state=success" ] && return 0
  done <"$STATUS_FILE"
  return 1
}

dump() {
  local label="$1" file="$2"
  [ -f "$file" ] || return 0
  say "----- begin $label ($file) -----"
  "$CU/cat" "$file"
  say "----- end $label -----"
}

main() {
  if [ ! -f "$WORKER" ]; then
    say "worker not present at $WORKER — nothing to do"
    exit 0
  fi

  "$CU/mkdir" -p -m 0700 "$STATE_DIR"

  local hash _rest
  read -r hash _rest < <("$CU/sha256sum" "$WORKER")
  say "worker present, sha256=$hash"

  local stamped=""
  [ -f "$STAMP" ] && read -r stamped <"$STAMP"

  if [ "$stamped" = "$hash" ] && status_is_success; then
    say "already satisfied: status reports state=success for this exact worker — skipping"
    exit 0
  fi

  # Guard against two of our own triggers overlapping (path unit + a manual
  # `systemctl restart`). Note this does NOT lock out Fleet: if Fleet ever
  # manages to run the worker itself it will not take this lock. That is
  # tolerable — the worker only verifies and rewrites its own status file, so
  # the worst case is interleaved log lines, not corruption.
  exec 9>"$LOCK"
  if ! "$FLOCK" -n 9; then
    say "another minerva-autorun run holds the lock — skipping"
    exit 0
  fi

  say "running worker as uid $EUID with PATH=$PATH"

  local rc=0
  "$BASH_BIN" "$WORKER" || rc=$?
  say "worker exited $rc"

  # The worker redirects all of its own output into its log file, so without
  # this the journal would be silent about what actually happened.
  dump "worker log" "$WORKER_LOG"
  dump "status file" "$STATUS_FILE"

  if [ "$rc" -ne 0 ]; then
    say "FAILED: worker exited $rc — NOT recording success"
    exit 1
  fi

  if ! status_is_success; then
    say "FAILED: worker exited 0 but its status file does not report state=success — NOT recording success"
    exit 1
  fi

  printf '%s\n' "$hash" >"$STAMP"
  say "SUCCESS: dependencies verified by the worker; stamped sha256=$hash"
}

main "$@"
