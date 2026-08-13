# shellcheck shell=bash
#
# minerva-apt-shim — a VERIFYING stand-in for apt-get/apt on NixOS.
#
# WHAT THIS IS
#   A tiny program named `apt-get` (and `apt`) that is put on the PATH of
#   *orbit* (the Fleet MDM agent) and therefore on the PATH of the scripts
#   Fleet pushes to this machine. It exists for exactly one reason: Shopify's
#   Minerva "install TPM/NSS dependencies" worker script hard-branches on
#   `command -v apt-get || pacman || dnf || yum` and aborts with
#   "unable to find apt-get, pacman, dnf, or yum" *before* it ever gets to
#   its own dependency verification. On NixOS none of those exist, so the
#   worker can never reach the checks it would otherwise pass.
#
# WHAT THIS IS NOT
#   It is NOT a package manager. It installs nothing, downloads nothing,
#   touches no state, and has no network access. The packages the worker
#   asks for are already provided declaratively by
#   machines/archon/minerva.nix in this repo.
#
# THE HONESTY PROPERTY (the whole point)
#   This shim never claims success for something that is not true.
#
#     * `apt-get update` is the only genuine no-op: it means "refresh package
#       metadata". On NixOS there is no metadata to refresh and the outcome
#       the caller cares about (that a subsequent install can succeed) is not
#       affected by it. It exits 0 and says so, loudly, in the log.
#
#     * `apt-get install P...` does NOT install. For every requested Debian
#       package name it looks up what that package is expected to *provide*
#       (commands on PATH, or a shared library discoverable exactly the way
#       the caller will look for it) and then CHECKS REALITY. It exits 0 if
#       and only if every single requested package is genuinely satisfied
#       right now, on the caller's own PATH. Otherwise it exits non-zero and
#       prints precisely what is missing.
#
#     * An unrecognised package name is a HARD FAILURE. Silence is not
#       consent: if we do not know what a package is supposed to provide, we
#       cannot honestly assert that it is present.
#
#     * An unrecognised command-line option is a HARD FAILURE, for the same
#       reason: we refuse to guess at semantics we do not implement.
#
#   Command lookups deliberately use the PATH we inherited, unmodified. The
#   shim pulls in no runtime inputs of its own precisely so that it cannot
#   accidentally "see" a tool that the calling script will not see. What it
#   asserts is exactly what the caller will observe.
#
#   Every invocation, with its full argument vector and its verdict, is
#   appended to the log file and sent to syslog, so there is an audit trail
#   of every assertion this thing has ever made.
#
# EXIT CODES
#   0  every requested package is genuinely satisfied (or: update no-op)
#   1  something was missing, unknown, or unsupported — nothing was faked
#
readonly SHIM_NAME="minerva-apt-shim"
readonly FIND="@find@"
readonly LOGGER="@logger@"

LOG_FILE="${MINERVA_APT_SHIM_LOG:-/var/log/minerva-apt-shim.log}"

# Directories searched for shared libraries. These are the same two the
# Minerva worker searches, in the same way, so a PASS here means the worker's
# own check will also pass.
readonly LIB_DIRS=(/usr/lib /usr/lib64)

now() {
  # bash builtin; avoids needing coreutils on PATH (see honesty note above).
  TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1
}

log() {
  local line
  line="$(now) [$SHIM_NAME] pid=$$ euid=$EUID $*"
  printf '%s\n' "$line" >&2
  { printf '%s\n' "$line" >>"$LOG_FILE"; } 2>/dev/null || true
  "$LOGGER" -t "$SHIM_NAME" -- "$*" 2>/dev/null || true
}

fail() {
  log "VERDICT=FAIL $*"
  exit 1
}

pass() {
  log "VERDICT=PASS $*"
  exit 0
}

# requirements_for <debian-package-name>
#
# Prints one requirement token per line, or returns 1 if the package is
# unknown to us. Token grammar:
#   cmd:NAME            NAME must be an executable on the inherited PATH
#   anycmd:N1,N2,...    at least one of N1,N2,... must be on the PATH
#   lib:BASENAME        a file matching BASENAME* must exist in a LIB_DIRS entry
requirements_for() {
  case "$1" in
  libtpm2-pkcs11-tools)
    printf '%s\n' 'cmd:tpm2_ptool'
    ;;
  libtpm2-pkcs11-1 | libtpm2-pkcs11-0)
    printf '%s\n' 'lib:libtpm2_pkcs11.so'
    ;;
  libnss3-tools)
    printf '%s\n' 'cmd:certutil' 'cmd:modutil'
    ;;
  gnupg | gnupg2)
    printf '%s\n' 'anycmd:gpg,gpg2'
    ;;
  curl)
    printf '%s\n' 'cmd:curl'
    ;;
  jq)
    printf '%s\n' 'cmd:jq'
    ;;
  coreutils)
    printf '%s\n' 'cmd:sha256sum' 'cmd:base64' 'cmd:install' 'cmd:date'
    ;;
  openssl)
    printf '%s\n' 'cmd:openssl'
    ;;
  *)
    return 1
    ;;
  esac
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

have_lib() {
  local pattern="$1" dir hits
  for dir in "${LIB_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    # NOTE: $dir must be a real directory, not a symlink — find does not
    # descend into a symlinked start directory. minerva.nix creates /usr/lib
    # as a real directory for exactly this reason.
    hits="$("$FIND" "$dir" -name "$pattern*" 2>/dev/null)" || hits=""
    [ -n "$hits" ] && return 0
  done
  return 1
}

# describe_unmet <token> -> human-readable reason, or empty if satisfied
unmet_reason() {
  local token="$1"
  case "$token" in
  cmd:*)
    local name="${token#cmd:}"
    have_cmd "$name" || printf 'command %s not found on PATH' "$name"
    ;;
  anycmd:*)
    local list="${token#anycmd:}" name found=0
    local IFS=,
    for name in $list; do
      if have_cmd "$name"; then
        found=1
        break
      fi
    done
    [ "$found" -eq 1 ] || printf 'none of the commands (%s) found on PATH' "$list"
    ;;
  lib:*)
    local pattern="${token#lib:}"
    have_lib "$pattern" || printf '%s* not found in %s' "$pattern" "${LIB_DIRS[*]}"
    ;;
  *)
    printf 'internal error: unknown requirement token %s' "$token"
    ;;
  esac
}

main() {
  log "INVOKED argv0=${0##*/} args=[$*] PATH=$PATH"

  local subcommand=""
  local -a packages=()
  local arg

  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in
    # Flags that are safe to accept and ignore: they change how a real apt
    # would behave while installing, and we never install.
    -y | --yes | --assume-yes | -q | -qq | --quiet | --no-install-recommends | \
      --no-install-suggests | --allow-* | --force-yes | -f | --fix-broken | \
      --fix-missing | -m | --no-upgrade | --only-upgrade | -s | --simulate | \
      --dry-run | --just-print | --recon | -V | --verbose-versions)
      ;;
    -o | --option | -t | --target-release)
      # These take a separate value argument; discard it too.
      shift || true
      ;;
    -o* | --option=* | --target-release=*)
      ;;
    --version)
      printf '%s: not apt. A verifying shim. See /etc/minerva/README or SHOPIFY.md.\n' "$SHIM_NAME"
      pass "reported identity for --version"
      ;;
    --)
      ;;
    -*)
      fail "refusing to guess the meaning of unrecognised option '$arg' (full args: [$*])"
      ;;
    *)
      if [ -z "$subcommand" ]; then
        subcommand="$arg"
      else
        packages+=("$arg")
      fi
      ;;
    esac
  done

  case "$subcommand" in
  update)
    pass "'update' is a genuine no-op on NixOS: there is no package index to refresh, and nothing was installed or changed"
    ;;
  install)
    ;;
  "")
    fail "no sub-command given; this shim only implements 'update' (no-op) and 'install' (verify-only)"
    ;;
  *)
    fail "sub-command '$subcommand' is not implemented by this shim; it only implements 'update' and 'install'"
    ;;
  esac

  if [ "${#packages[@]}" -eq 0 ]; then
    fail "'install' was called with no package names"
  fi

  local -a unknown=() unsatisfied=() satisfied=()
  local pkg reqs token reason

  for pkg in "${packages[@]}"; do
    if ! reqs="$(requirements_for "$pkg")"; then
      unknown+=("$pkg")
      continue
    fi
    local pkg_ok=1
    while IFS= read -r token; do
      [ -n "$token" ] || continue
      reason="$(unmet_reason "$token")"
      if [ -n "$reason" ]; then
        pkg_ok=0
        unsatisfied+=("$pkg: $reason")
      fi
    done <<<"$reqs"
    if [ "$pkg_ok" -eq 1 ]; then
      satisfied+=("$pkg")
    fi
  done

  if [ "${#unknown[@]}" -ne 0 ]; then
    fail "unknown package name(s), cannot honestly assert anything about them: ${unknown[*]}"
  fi

  if [ "${#unsatisfied[@]}" -ne 0 ]; then
    local joined
    printf -v joined '%s; ' "${unsatisfied[@]}"
    fail "requested packages are NOT satisfied on this system: ${joined%; }"
  fi

  pass "verified (not installed) — every requested package is genuinely present: ${satisfied[*]}"
}

main "$@"
