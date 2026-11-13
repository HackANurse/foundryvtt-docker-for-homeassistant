#!/usr/bin/env bash
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-update-launch.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT INT TERM

# shellcheck source=../foundryvtt/update.sh
. "${repo_root}/foundryvtt/update.sh"

if ! type confirm_pending_update >/dev/null 2>&1 \
  || ! type rollback_pending_update >/dev/null 2>&1; then
  echo "missing production state transition functions" >&2
  exit 1
fi
if [ ! -x "${repo_root}/foundryvtt/launch.sh" ]; then
  echo "missing executable: foundryvtt/launch.sh" >&2
  exit 1
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_no_path() {
  [ ! -e "$1" ] || fail "unexpected path: $1"
}

write_app() {
  application_root="$1"
  version="$2"
  marker="$3"
  generation="${version%%.*}"
  build="${version#*.}"
  mkdir -p "${application_root}/resources/app"
  printf '{"release":{"generation":%s,"build":%s}}\n' \
    "${generation}" "${build}" > "${application_root}/resources/app/package.json"
  printf '%s\n' "${marker}" > "${application_root}/resources/app/main.mjs"
}

make_pending_root() {
  root="$1"
  for directory in Data Config Backups Logs container_cache; do
    mkdir -p "${root}/${directory}"
    printf '%s sentinel\n' "${directory}" > "${root}/${directory}/sentinel.txt"
  done
  write_app "${root}/foundry_app" 14.370 new-app
  write_app "${root}/foundry_app.previous" 14.369 old-app
  mkdir -p "${root}/.foundry-update"
  printf '{"version":"14.370","fingerprint":"target:14.370"}\n' \
    > "${root}/.foundry-update/pending.json"
  printf 'cached\n' > "${root}/container_cache/foundryvtt-14.370.zip"
}

assert_user_data_preserved() {
  root="$1"
  for directory in Data Config Backups Logs; do
    assert_file "${root}/${directory}/sentinel.txt"
  done
}

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

healthy_entrypoint="${test_root}/healthy-entrypoint.sh"
cat > "${healthy_entrypoint}" <<'EOF'
#!/usr/bin/env bash
exec python3 -c 'import socket,time,os; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",int(os.environ["TEST_HEALTH_PORT"]))); s.listen(); time.sleep(1.5)'
EOF

failing_entrypoint="${test_root}/failing-entrypoint.sh"
cat > "${failing_entrypoint}" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF

clean_exit_entrypoint="${test_root}/clean-exit-entrypoint.sh"
cat > "${clean_exit_entrypoint}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

sleeping_entrypoint="${test_root}/sleeping-entrypoint.sh"
cat > "${sleeping_entrypoint}" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF

signal_entrypoint="${test_root}/signal-entrypoint.sh"
cat > "${signal_entrypoint}" <<'EOF'
#!/usr/bin/env bash
trap 'printf "forwarded\n" > "${TEST_SIGNAL_MARKER}"; exit 0' TERM INT
while :; do sleep 1; done
EOF

chmod 0755 "${healthy_entrypoint}" "${failing_entrypoint}" \
  "${clean_exit_entrypoint}" \
  "${sleeping_entrypoint}" "${signal_entrypoint}"

# Confirmation must preserve rollback state when completed.json is unusable.
case_root="${test_root}/confirm-state-failure"
make_pending_root "${case_root}"
mkdir -p "${case_root}/.foundry-update/completed.json"
if confirm_pending_update "${case_root}" >/dev/null 2>&1; then
  fail "confirmation unexpectedly accepted a directory as completed state"
fi
assert_file "${case_root}/.foundry-update/pending.json"
assert_file "${case_root}/foundry_app.previous/resources/app/main.mjs"

# A reachable first launch confirms the update and discards the rollback copy.
case_root="${test_root}/healthy"
make_pending_root "${case_root}"
health_port="$(free_port)"
FOUNDRY_DATA_PATH="${case_root}" \
FOUNDRY_HEALTH_PORT="${health_port}" \
FOUNDRY_HEALTH_TIMEOUT=5 \
FOUNDRY_HEALTH_INTERVAL=0.1 \
TEST_HEALTH_PORT="${health_port}" \
  "${repo_root}/foundryvtt/launch.sh" "${healthy_entrypoint}"
assert_no_path "${case_root}/foundry_app.previous"
assert_no_path "${case_root}/.foundry-update/pending.json"
assert_file "${case_root}/.foundry-update/completed.json"
assert_file "${case_root}/container_cache/foundryvtt-14.370.zip"
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = new-app ] \
  || fail "healthy launch did not keep the new application"
assert_user_data_preserved "${case_root}"

# A clean child exit before health is still a failed first launch.
case_root="${test_root}/clean-early-exit"
make_pending_root "${case_root}"
set +e
FOUNDRY_DATA_PATH="${case_root}" \
FOUNDRY_HEALTH_PORT="$(free_port)" \
FOUNDRY_HEALTH_TIMEOUT=2 \
FOUNDRY_HEALTH_INTERVAL=0.1 \
  "${repo_root}/foundryvtt/launch.sh" "${clean_exit_entrypoint}"
launch_status=$?
set -e
[ "${launch_status}" -ne 0 ] || fail "clean exit before health should fail the launch"
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = old-app ] \
  || fail "clean early exit did not restore the previous application"
assert_file "${case_root}/.foundry-update/failed.json"

# A child that exits before health restores the previous application.
case_root="${test_root}/early-exit"
make_pending_root "${case_root}"
set +e
FOUNDRY_DATA_PATH="${case_root}" \
FOUNDRY_HEALTH_PORT="$(free_port)" \
FOUNDRY_HEALTH_TIMEOUT=2 \
FOUNDRY_HEALTH_INTERVAL=0.1 \
  "${repo_root}/foundryvtt/launch.sh" "${failing_entrypoint}"
launch_status=$?
set -e
[ "${launch_status}" -eq 23 ] || fail "early exit should preserve child status 23"
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = old-app ] \
  || fail "early exit did not restore the previous application"
assert_no_path "${case_root}/foundry_app.previous"
assert_no_path "${case_root}/.foundry-update/pending.json"
assert_file "${case_root}/.foundry-update/failed.json"
assert_user_data_preserved "${case_root}"

# A child that never becomes healthy is stopped and rolled back.
case_root="${test_root}/timeout"
make_pending_root "${case_root}"
set +e
FOUNDRY_DATA_PATH="${case_root}" \
FOUNDRY_HEALTH_PORT="$(free_port)" \
FOUNDRY_HEALTH_TIMEOUT=1 \
FOUNDRY_HEALTH_INTERVAL=0.1 \
  "${repo_root}/foundryvtt/launch.sh" "${sleeping_entrypoint}"
launch_status=$?
set -e
[ "${launch_status}" -ne 0 ] || fail "health timeout should fail"
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = old-app ] \
  || fail "timeout did not restore the previous application"
assert_file "${case_root}/.foundry-update/failed.json"
assert_user_data_preserved "${case_root}"

# Normal startup forwards TERM to the child exactly as PID 1 must.
case_root="${test_root}/signal"
mkdir -p "${case_root}"
signal_marker="${test_root}/signal-forwarded.txt"
FOUNDRY_DATA_PATH="${case_root}" \
TEST_SIGNAL_MARKER="${signal_marker}" \
  "${repo_root}/foundryvtt/launch.sh" "${signal_entrypoint}" &
launcher_pid=$!
sleep 0.3
kill -TERM "${launcher_pid}"
wait "${launcher_pid}"
assert_file "${signal_marker}"
[ "$(wc -l < "${signal_marker}" | tr -d ' ')" = 1 ] \
  || fail "TERM was not forwarded exactly once"

echo "PASS: update launch confirmation and rollback"
