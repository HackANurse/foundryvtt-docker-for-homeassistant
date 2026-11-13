#!/usr/bin/env bash
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_helper="${repo_root}/tests/helpers/make_foundry_fixture.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-update-transaction.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT INT TERM

# shellcheck source=../foundryvtt/update.sh
. "${repo_root}/foundryvtt/update.sh"

if ! type perform_requested_update >/dev/null 2>&1; then
  echo "missing production function: perform_requested_update" >&2
  exit 1
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "unexpected path: $1"
}

make_config_root() {
  root="$1"
  version="$2"
  for directory in Data Config Backups Logs container_cache; do
    mkdir -p "${root}/${directory}"
    printf '%s sentinel\n' "${directory}" > "${root}/${directory}/sentinel.txt"
  done
  mkdir -p "${root}/foundry_app/resources/app"
  generation="${version%%.*}"
  build="${version#*.}"
  printf '{"release":{"generation":%s,"build":%s}}\n' \
    "${generation}" "${build}" > "${root}/foundry_app/resources/app/package.json"
  printf 'old app\n' > "${root}/foundry_app/resources/app/main.mjs"
}

assert_user_data_preserved() {
  root="$1"
  for directory in Data Config Backups Logs; do
    assert_file "${root}/${directory}/sentinel.txt"
  done
}

release_370="${test_root}/foundry-14.370.zip"
release_371="${test_root}/foundry-14.371.zip"
"${fixture_helper}" "${release_370}" 14.370 node
"${fixture_helper}" "${release_371}" 14.371 linux
url_370="file://${release_370}"
url_371="file://${release_371}"

# Version plus URL: install the exact requested release and retain rollback.
case_root="${test_root}/version-url"
make_config_root "${case_root}" 14.369
perform_requested_update 14.370 "${url_370}" "" "" "${case_root}"
assert_file "${case_root}/foundry_app/resources/app/package.json"
assert_file "${case_root}/foundry_app.previous/resources/app/package.json"
assert_file "${case_root}/.foundry-update/pending.json"
assert_user_data_preserved "${case_root}"
[ "$(jq -r '.version' "${case_root}/.foundry-update/pending.json")" = 14.370 ] \
  || fail "pending state should record 14.370"

# URL-only: infer the release version from the archive.
case_root="${test_root}/url-only"
make_config_root "${case_root}" 14.369
perform_requested_update "" "${url_371}" "" "" "${case_root}"
[ "$(jq -r '.release | "\(.generation).\(.build)"' \
  "${case_root}/foundry_app/resources/app/package.json")" = 14.371 ] \
  || fail "URL-only request should infer 14.371"
assert_user_data_preserved "${case_root}"

# Target mismatch must fail without moving the live application.
case_root="${test_root}/mismatch"
make_config_root "${case_root}" 14.369
if perform_requested_update 14.370 "${url_371}" "" "" "${case_root}" >/dev/null 2>&1; then
  fail "target mismatch unexpectedly succeeded"
fi
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = "old app" ] \
  || fail "target mismatch changed the live application"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

# Expired/unreadable URL must preserve the live application.
case_root="${test_root}/expired"
make_config_root "${case_root}" 14.369
if perform_requested_update 14.370 "file://${test_root}/missing.zip" "" "" "${case_root}" \
  >/dev/null 2>&1; then
  fail "missing URL unexpectedly succeeded"
fi
assert_file "${case_root}/foundry_app/resources/app/main.mjs"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

# Invalid extraction must preserve the live application.
case_root="${test_root}/invalid"
make_config_root "${case_root}" 14.369
printf 'not a zip\n' > "${test_root}/invalid.zip"
if perform_requested_update 14.370 "file://${test_root}/invalid.zip" "" "" "${case_root}" \
  >/dev/null 2>&1; then
  fail "invalid archive unexpectedly succeeded"
fi
assert_file "${case_root}/foundry_app/resources/app/main.mjs"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

# An occupied rollback path must stop promotion before the live rename.
case_root="${test_root}/occupied-rollback"
make_config_root "${case_root}" 14.369
printf 'occupied\n' > "${case_root}/foundry_app.previous"
if perform_requested_update 14.370 "${url_370}" "" "" "${case_root}" >/dev/null 2>&1; then
  fail "occupied rollback path unexpectedly succeeded"
fi
assert_file "${case_root}/foundry_app/resources/app/main.mjs"
[ "$(cat "${case_root}/foundry_app.previous")" = occupied ] \
  || fail "occupied rollback marker changed"
assert_user_data_preserved "${case_root}"

# Version plus credentials resolves an exact URL through the bundled helpers.
case_root="${test_root}/credentials"
make_config_root "${case_root}" 14.369
fake_home="${test_root}/fake-home"
mkdir -p "${fake_home}"
touch "${fake_home}/authenticate.js" "${fake_home}/get_release_url.js"
fake_node="${test_root}/fake-node"
cat > "${fake_node}" <<'EOF'
#!/usr/bin/env bash
set -eu
script="$1"
shift
case "${script}" in
  */authenticate.js)
    cookie=""
    for argument in "$@"; do cookie="${argument}"; done
    printf '{}\n' > "${cookie}"
    ;;
  */get_release_url.js)
    printf '%s\n' "${FAKE_RELEASE_URL}"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${fake_node}"
credential_output="$(
  FOUNDRY_UPDATE_HOME="${fake_home}" \
  FOUNDRY_UPDATE_NODE_BIN="${fake_node}" \
  FAKE_RELEASE_URL="${url_370}" \
    perform_requested_update 14.370 "" private-user private-password "${case_root}"
)"
case "${credential_output}" in
  *private-user*|*private-password*|*"${url_370}"*)
    fail "credential flow leaked a secret or signed URL"
    ;;
esac
assert_file "${case_root}/foundry_app/resources/app/package.json"
assert_no_file "${case_root}/.foundry-update/cookiejar.json"
assert_user_data_preserved "${case_root}"

# Neither target nor URL is not a valid request.
case_root="${test_root}/empty"
make_config_root "${case_root}" 14.369
if perform_requested_update "" "" user password "${case_root}" >/dev/null 2>&1; then
  fail "empty request unexpectedly succeeded"
fi
assert_file "${case_root}/foundry_app/resources/app/main.mjs"

# Manual update mode requires an existing application for rollback.
case_root="${test_root}/no-existing-app"
mkdir -p "${case_root}/Data" "${case_root}/Config" "${case_root}/Backups" \
  "${case_root}/Logs" "${case_root}/container_cache"
if perform_requested_update 14.370 "${url_370}" "" "" "${case_root}" >/dev/null 2>&1; then
  fail "manual update without an existing application unexpectedly succeeded"
fi
assert_no_file "${case_root}/foundry_app"
assert_no_file "${case_root}/foundry_app.previous"

# A completed target request is idempotent and does not need a usable URL.
case_root="${test_root}/idempotent-target"
make_config_root "${case_root}" 14.370
mkdir -p "${case_root}/.foundry-update"
printf '{"version":"14.370","fingerprint":"target:14.370"}\n' \
  > "${case_root}/.foundry-update/completed.json"
perform_requested_update 14.370 "file://${test_root}/must-not-download.zip" "" "" "${case_root}"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

# A completed URL-only request is also idempotent without another download.
case_root="${test_root}/idempotent-url"
make_config_root "${case_root}" 14.371
mkdir -p "${case_root}/.foundry-update"
url_fingerprint="url:$(printf '%s' "${url_371}" | shasum -a 256 | awk '{print $1}')"
printf '{"version":"14.371","fingerprint":"%s"}\n' "${url_fingerprint}" \
  > "${case_root}/.foundry-update/completed.json"
perform_requested_update "" "${url_371}" "" "" "${case_root}"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

# A failed request must not retry until the UI toggle has been reset to false.
case_root="${test_root}/failed-one-shot"
make_config_root "${case_root}" 14.369
mkdir -p "${case_root}/.foundry-update"
printf '{"version":"14.370","fingerprint":"target:14.370","failed":true}\n' \
  > "${case_root}/.foundry-update/failed.json"
perform_requested_update 14.370 "${url_370}" "" "" "${case_root}" >/dev/null 2>&1 \
  || fail "failed one-shot request should keep running the restored application"
[ "$(cat "${case_root}/foundry_app/resources/app/main.mjs")" = "old app" ] \
  || fail "failed one-shot retry changed the live application"
assert_no_file "${case_root}/foundry_app.previous"
assert_user_data_preserved "${case_root}"

echo "PASS: transactional update requests"
