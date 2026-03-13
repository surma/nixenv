#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/modules/services/key-poller/key-poller.nu"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local needle=$1
  local file=$2
  grep -Fqx "$needle" "$file" || fail "expected '$needle' in $file"
}

assert_not_exists_or_empty() {
  local file=$1
  if [[ -e "$file" && -s "$file" ]]; then
    fail "expected $file to be missing or empty"
  fi
}

setup_case() {
  local dir=$1

  mkdir -p "$dir/bin" "$dir/state"
  printf 'secret\n' > "$dir/receiver-secret"

  cat > "$dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_TMP:?}"

host=""
for arg in "$@"; do
  case "$arg" in
    *"@10.0.0.20") host="10.0.0.20" ;;
    *"@100.79.232.5") host="100.79.232.5" ;;
  esac
done

[[ -n "$host" ]] || {
  echo "missing host" >&2
  exit 91
}

printf '%s\n' "$host" >> "$TEST_TMP/ssh-hosts.log"

case "$host" in
  10.0.0.20)
    mode="${SSH_10_MODE:-success}"
    key="${SSH_10_KEY:-key-from-10}"
    ;;
  100.79.232.5)
    mode="${SSH_100_MODE:-success}"
    key="${SSH_100_KEY:-key-from-100}"
    ;;
  *)
    echo "unexpected host: $host" >&2
    exit 92
    ;;
esac

case "$mode" in
  success)
    printf '%s\n' "$key"
    ;;
  empty)
    printf '\n'
    ;;
  fail)
    echo "$host failed" >&2
    exit 1
    ;;
  *)
    echo "unexpected mode: $mode" >&2
    exit 93
    ;;
esac
EOF
  chmod +x "$dir/bin/ssh"

  cat > "$dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_TMP:?}"

printf '%s\n' "$*" >> "$TEST_TMP/curl-args.log"

mode="${CURL_MODE:-success}"
data=""
next_is_data=0
for arg in "$@"; do
  if [[ "$next_is_data" == 1 ]]; then
    data="$arg"
    next_is_data=0
    continue
  fi
  if [[ "$arg" == "--data-binary" ]]; then
    next_is_data=1
  fi
done

if [[ -n "$data" ]]; then
  printf '%s\n' "$data" > "$TEST_TMP/posted-key"
fi

case "$mode" in
  success)
    printf 'ok\n'
    ;;
  fail)
    echo 'curl failed' >&2
    exit 1
    ;;
  *)
    echo "unexpected curl mode: $mode" >&2
    exit 94
    ;;
esac
EOF
  chmod +x "$dir/bin/curl"

  cat > "$dir/bin/jwt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="${JWT_MODE:-success}"
case "$mode" in
  success)
    printf 'jwt-token\n'
    ;;
  fail)
    echo 'jwt failed' >&2
    exit 1
    ;;
  *)
    echo "unexpected jwt mode: $mode" >&2
    exit 95
    ;;
esac
EOF
  chmod +x "$dir/bin/jwt"
}

run_key_poller() {
  local dir=$1
  shift
  TEST_TMP="$dir" \
  KEY_POLLER_SSH_BIN="$dir/bin/ssh" \
  KEY_POLLER_CURL_BIN="$dir/bin/curl" \
  KEY_POLLER_JWT_BIN="$dir/bin/jwt" \
  KEY_POLLER_SSH_USER="surma" \
  KEY_POLLER_SSH_IDENTITY_FILE="$dir/id_machine" \
  KEY_POLLER_KNOWN_HOSTS_FILE="$dir/state/known_hosts" \
  KEY_POLLER_SSH_HOSTS_JSON='["10.0.0.20","100.79.232.5"]' \
  KEY_POLLER_RECEIVER_URL="https://key.llm.surma.technology" \
  KEY_POLLER_SECRET_FILE="$dir/receiver-secret" \
  KEY_POLLER_REMOTE_NU_BIN="/remote/nu" \
  KEY_POLLER_REMOTE_GCLOUD_BIN="/remote/gcloud" \
  "$@" \
  nu "$SCRIPT"
}

test_success_on_first_host() {
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  setup_case "$dir"

  SSH_10_MODE=success SSH_10_KEY=key-from-first SSH_100_MODE=fail \
    run_key_poller "$dir" >"$dir/stdout" 2>"$dir/stderr" || fail "expected success on first host"

  assert_contains "10.0.0.20" "$dir/ssh-hosts.log"
  [[ "$(wc -l < "$dir/ssh-hosts.log")" == "1" ]] || fail "expected only first host to be tried"
  [[ "$(< "$dir/posted-key")" == "key-from-first" ]] || fail "expected posted key from first host"
}

test_falls_back_to_second_host() {
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  setup_case "$dir"

  SSH_10_MODE=fail SSH_100_MODE=success SSH_100_KEY=key-from-second \
    run_key_poller "$dir" >"$dir/stdout" 2>"$dir/stderr" || fail "expected fallback to second host"

  mapfile -t hosts < "$dir/ssh-hosts.log"
  [[ "${#hosts[@]}" == "2" ]] || fail "expected both hosts to be tried"
  [[ "${hosts[0]}" == "10.0.0.20" ]] || fail "expected first attempt on 10.0.0.20"
  [[ "${hosts[1]}" == "100.79.232.5" ]] || fail "expected fallback attempt on 100.79.232.5"
  [[ "$(< "$dir/posted-key")" == "key-from-second" ]] || fail "expected posted key from second host"
}

test_fails_when_all_hosts_fail() {
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  setup_case "$dir"

  if SSH_10_MODE=fail SSH_100_MODE=fail run_key_poller "$dir" >"$dir/stdout" 2>"$dir/stderr"; then
    fail "expected failure when all hosts fail"
  fi

  mapfile -t hosts < "$dir/ssh-hosts.log"
  [[ "${#hosts[@]}" == "2" ]] || fail "expected both hosts to be tried on total failure"
  assert_not_exists_or_empty "$dir/posted-key"
}

test_fails_on_empty_key() {
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  setup_case "$dir"

  if SSH_10_MODE=empty SSH_100_MODE=fail run_key_poller "$dir" >"$dir/stdout" 2>"$dir/stderr"; then
    fail "expected failure on empty key"
  fi

  assert_not_exists_or_empty "$dir/posted-key"
}

test_success_on_first_host
test_falls_back_to_second_host
test_fails_when_all_hosts_fail
test_fails_on_empty_key

echo "PASS: key-poller tests"
