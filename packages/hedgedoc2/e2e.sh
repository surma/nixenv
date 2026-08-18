#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /nix/store/...-hedgedoc2-...\n' "$0" >&2
  exit 2
fi

for command_name in caddy curl jq python3; do
  if ! command -v "$command_name" >/dev/null; then
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 2
  fi
done

package=$(realpath "$1")
backend="$package/bin/hedgedoc2-backend"
frontend="$package/bin/hedgedoc2-frontend"

if [[ ! -x "$backend" || ! -x "$frontend" ]]; then
  printf 'The package does not contain both HedgeDoc executables: %s\n' "$package" >&2
  exit 2
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/hedgedoc2-e2e.XXXXXXXX")
process_ids=()

print_logs() {
  local component
  for component in backend frontend caddy; do
    printf '\n===== %s stdout =====\n' "$component" >&2
    if [[ -f "$test_root/$component.stdout.log" ]]; then
      cat "$test_root/$component.stdout.log" >&2
    fi
    printf '\n===== %s stderr =====\n' "$component" >&2
    if [[ -f "$test_root/$component.stderr.log" ]]; then
      cat "$test_root/$component.stderr.log" >&2
    fi
  done
}

cleanup() {
  local status=$?
  local process_id

  trap - EXIT
  for process_id in "${process_ids[@]}"; do
    kill "$process_id" 2>/dev/null || true
  done
  sleep 0.2
  for process_id in "${process_ids[@]}"; do
    if kill -0 "$process_id" 2>/dev/null; then
      kill -KILL "$process_id" 2>/dev/null || true
    fi
    wait "$process_id" 2>/dev/null || true
  done

  if [[ $status -ne 0 ]]; then
    print_logs
    printf '\nTest artifacts remain at %s\n' "$test_root" >&2
  else
    rm -rf "$test_root"
  fi

  exit "$status"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

trap cleanup EXIT
trap 'exit 130' INT TERM

read -r backend_port frontend_port proxy_port < <(
  python3 - <<'PY'
import socket

sockets = [socket.socket() for _ in range(3)]
for listener in sockets:
    listener.bind(("127.0.0.1", 0))
print(*(listener.getsockname()[1] for listener in sockets))
PY
)

base_url="http://127.0.0.1:$proxy_port"
database="$test_root/hedgedoc.sqlite"
uploads="$test_root/uploads"
cookie_jar="$test_root/cookies.txt"
mkdir -p "$uploads"
: >"$cookie_jar"

wait_for_http() {
  local name=$1
  local url=$2
  local process_id=$3
  local output=$4
  local attempt

  for ((attempt = 1; attempt <= 120; attempt++)); do
    if curl \
      --noproxy '*' \
      --silent \
      --show-error \
      --fail \
      --max-time 2 \
      --output "$output" \
      "$url" \
      >"$test_root/$name-probe.stdout.log" \
      2>"$test_root/$name-probe.stderr.log"; then
      return 0
    fi
    if ! kill -0 "$process_id" 2>/dev/null; then
      fail "$name stopped before its readiness probe passed"
    fi
    sleep 0.25
  done

  fail "$name did not become ready at $url"
}

expect_http() {
  local expected_status=$1
  local method=$2
  local url=$3
  local output=$4
  shift 4
  local actual_status

  actual_status=$(
    curl \
      --noproxy '*' \
      --silent \
      --show-error \
      --max-time 15 \
      --request "$method" \
      --output "$output" \
      --write-out '%{http_code}' \
      "$@" \
      "$url"
  )

  if [[ "$actual_status" != "$expected_status" ]]; then
    printf 'Expected HTTP %s from %s %s, but received %s.\n' \
      "$expected_status" "$method" "$url" "$actual_status" >&2
    if [[ -s "$output" ]]; then
      printf 'Response body:\n' >&2
      cat "$output" >&2
      printf '\n' >&2
    fi
    exit 1
  fi
}

get_csrf_token() {
  local output=$1
  expect_http 200 GET "$base_url/api/private/csrf/token" "$output" \
    --cookie "$cookie_jar" \
    --cookie-jar "$cookie_jar"
  jq --exit-status --raw-output \
    '.token | select(type == "string" and length > 0)' \
    "$output"
}

env \
  HD_BASE_URL="$base_url" \
  HD_RENDERER_BASE_URL="$base_url" \
  HD_BACKEND_PORT="$backend_port" \
  HD_BACKEND_BIND_IP=127.0.0.1 \
  HD_DATABASE_TYPE=sqlite \
  HD_DATABASE_NAME="$database" \
  HD_AUTH_SESSION_SECRET=native-nix-e2e-session-secret-0123456789 \
  HD_AUTH_LOCAL_ENABLE_LOGIN=true \
  HD_AUTH_LOCAL_ENABLE_REGISTER=true \
  HD_AUTH_LOCAL_MINIMAL_PASSWORD_STRENGTH=0 \
  HD_MEDIA_BACKEND_TYPE=filesystem \
  HD_MEDIA_BACKEND_FILESYSTEM_UPLOAD_PATH="$uploads" \
  HD_NOTE_PERMISSIONS_MAX_GUEST_LEVEL=write \
  HD_LOG_LEVEL=info \
  HD_LOG_SHOW_TIMESTAMP=false \
  "$backend" \
  >"$test_root/backend.stdout.log" \
  2>"$test_root/backend.stderr.log" &
process_ids+=("$!")
backend_pid=$!

wait_for_http \
  backend \
  "http://127.0.0.1:$backend_port/api/private/config" \
  "$backend_pid" \
  "$test_root/backend-config.json"
jq --exit-status \
  '.allowRegister == true and any(.authProviders[]; .type == "local")' \
  "$test_root/backend-config.json" \
  >/dev/null

env \
  HOSTNAME=127.0.0.1 \
  PORT="$frontend_port" \
  HD_BASE_URL="$base_url" \
  HD_RENDERER_BASE_URL="$base_url" \
  HD_INTERNAL_API_URL="http://127.0.0.1:$backend_port" \
  "$frontend" \
  >"$test_root/frontend.stdout.log" \
  2>"$test_root/frontend.stderr.log" &
process_ids+=("$!")
frontend_pid=$!

wait_for_http \
  frontend \
  "http://127.0.0.1:$frontend_port/login" \
  "$frontend_pid" \
  "$test_root/frontend-login.html"
[[ -s "$test_root/frontend-login.html" ]] || fail 'The direct frontend response is empty'
grep --quiet 'HedgeDoc' "$test_root/frontend-login.html" || \
  fail 'The direct frontend response does not identify HedgeDoc'

cat >"$test_root/Caddyfile" <<EOF
{
  admin off
  auto_https off
}

http://127.0.0.1:$proxy_port {
  log {
    output stdout
    level WARN
    format console
  }

  reverse_proxy /realtime http://127.0.0.1:$backend_port
  reverse_proxy /api/* http://127.0.0.1:$backend_port
  reverse_proxy /public/* http://127.0.0.1:$backend_port
  reverse_proxy /media/* http://127.0.0.1:$backend_port
  reverse_proxy /* http://127.0.0.1:$frontend_port
}
EOF

env \
  XDG_CONFIG_HOME="$test_root/xdg-config" \
  XDG_DATA_HOME="$test_root/xdg-data" \
  caddy run \
    --config "$test_root/Caddyfile" \
    --adapter caddyfile \
  >"$test_root/caddy.stdout.log" \
  2>"$test_root/caddy.stderr.log" &
process_ids+=("$!")
caddy_pid=$!

wait_for_http \
  proxy \
  "$base_url/login" \
  "$caddy_pid" \
  "$test_root/proxy-login.html"
[[ -s "$test_root/proxy-login.html" ]] || fail 'The proxied frontend response is empty'
grep --quiet 'HedgeDoc' "$test_root/proxy-login.html" || \
  fail 'The proxied frontend response does not identify HedgeDoc'

expect_http \
  200 GET "$base_url/api/private/config" "$test_root/proxy-config.json"
jq --exit-status \
  '.allowRegister == true and any(.authProviders[]; .type == "local")' \
  "$test_root/proxy-config.json" \
  >/dev/null

username=scout
password='native-nix-e2e-password-0123456789'
csrf_token=$(get_csrf_token "$test_root/csrf-register.json")
registration_payload=$(
  jq --null-input --compact-output \
    --arg username "$username" \
    --arg displayName 'Scout Test' \
    --arg password "$password" \
    '{username: $username, displayName: $displayName, password: $password}'
)
expect_http \
  201 POST "$base_url/api/private/auth/local" "$test_root/register.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar" \
  --header "CSRF-Token: $csrf_token" \
  --header 'Content-Type: application/json' \
  --data "$registration_payload"

expect_http \
  200 GET "$base_url/api/private/me" "$test_root/me-after-register.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar"
jq --exit-status \
  --arg username "$username" \
  '.username == $username and .authProvider == "local"' \
  "$test_root/me-after-register.json" \
  >/dev/null

expect_http \
  200 DELETE "$base_url/api/private/auth/logout" "$test_root/logout.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar" \
  --header "CSRF-Token: $csrf_token"
: >"$cookie_jar"

csrf_token=$(get_csrf_token "$test_root/csrf-login.json")
login_payload=$(
  jq --null-input --compact-output \
    --arg username "$username" \
    --arg password "$password" \
    '{username: $username, password: $password}'
)
expect_http \
  201 POST "$base_url/api/private/auth/local/login" "$test_root/login.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar" \
  --header "CSRF-Token: $csrf_token" \
  --header 'Content-Type: application/json' \
  --data "$login_payload"

expect_http \
  200 GET "$base_url/api/private/me" "$test_root/me-after-login.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar"
jq --exit-status \
  --arg username "$username" \
  '.username == $username and .authProvider == "local"' \
  "$test_root/me-after-login.json" \
  >/dev/null

expect_http \
  201 POST "$base_url/api/private/tokens" "$test_root/token.json" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar" \
  --header "CSRF-Token: $csrf_token" \
  --header 'Content-Type: application/json' \
  --data '{"label":"nix-e2e"}'
api_token=$(
  jq --exit-status --raw-output \
    '.secret | select(type == "string" and startswith("hd2.") and length > 20)' \
    "$test_root/token.json"
)

printf '%s' \
  $'# Native Nix HedgeDoc test\n\nThis note contains the initial content.' \
  >"$test_root/initial.md"
printf '%s' \
  $'# Native Nix HedgeDoc test\n\nThis note contains the replacement content after PUT.' \
  >"$test_root/replacement.md"

expect_http \
  201 POST "$base_url/api/v2/notes" "$test_root/note-create.json" \
  --header "Authorization: Bearer $api_token" \
  --header 'Content-Type: text/markdown' \
  --data-binary "@$test_root/initial.md"
note_alias=$(
  jq --exit-status --raw-output \
    '.metadata.primaryAlias | select(type == "string" and length > 0)' \
    "$test_root/note-create.json"
)

expect_http \
  200 GET "$base_url/api/v2/notes/$note_alias" "$test_root/note-read.json" \
  --header "Authorization: Bearer $api_token"
jq --exit-status \
  --rawfile expected "$test_root/initial.md" \
  '.content == $expected' \
  "$test_root/note-read.json" \
  >/dev/null

expect_http \
  200 PUT "$base_url/api/v2/notes/$note_alias" "$test_root/note-update.json" \
  --header "Authorization: Bearer $api_token" \
  --header 'Content-Type: text/markdown' \
  --data-binary "@$test_root/replacement.md"
jq --exit-status \
  --rawfile expected "$test_root/replacement.md" \
  '.content == $expected' \
  "$test_root/note-update.json" \
  >/dev/null

expect_http \
  200 GET "$base_url/api/v2/notes/$note_alias" "$test_root/note-reread.json" \
  --header "Authorization: Bearer $api_token"
jq --exit-status \
  --rawfile expected "$test_root/replacement.md" \
  '.content == $expected' \
  "$test_root/note-reread.json" \
  >/dev/null

[[ -s "$database" ]] || fail 'The SQLite database is absent or empty'

printf 'HedgeDoc 2 end-to-end test passed.\n'
printf 'Verified backend, frontend, SQLite, local login, API tokens, and note create/read/PUT/reread.\n'
