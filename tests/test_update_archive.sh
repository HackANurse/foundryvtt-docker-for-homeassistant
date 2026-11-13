#!/usr/bin/env bash
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_helper="${repo_root}/tests/helpers/make_foundry_fixture.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-update-archive.XXXXXX")"

trap 'rm -rf "${test_root}"' EXIT INT TERM

# shellcheck source=../foundryvtt/update.sh
if [ ! -f "${repo_root}/foundryvtt/update.sh" ]; then
  echo "missing production script: foundryvtt/update.sh" >&2
  exit 1
fi
. "${repo_root}/foundryvtt/update.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_equals() {
  expected="$1"
  actual="$2"
  message="$3"
  [ "${actual}" = "${expected}" ] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_rejected() {
  message="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${message}: command unexpectedly succeeded"
  fi
}

node_zip="${test_root}/foundry-node.zip"
linux_zip="${test_root}/foundry-linux.zip"
bad_generation_zip="${test_root}/foundry-v15.zip"
"${fixture_helper}" "${node_zip}" 14.370 node
"${fixture_helper}" "${linux_zip}" 14.370 linux
"${fixture_helper}" "${bad_generation_zip}" 15.370 node

validate_foundry_version 14.370 || fail "14.370 should be accepted"
assert_rejected "missing build" validate_foundry_version 14
assert_rejected "non-numeric build" validate_foundry_version 14.latest
assert_rejected "different generation" validate_foundry_version 15.370

assert_equals 14.370 "$(archive_foundry_version "${node_zip}")" "node archive version"
assert_equals 14.370 "$(archive_foundry_version "${linux_zip}")" "linux archive version"
assert_rejected "generation 15 archive" archive_foundry_version "${bad_generation_zip}"

printf 'not a zip\n' > "${test_root}/malformed.zip"
assert_rejected "malformed archive" archive_foundry_version "${test_root}/malformed.zip"

assert_rejected "target mismatch" \
  stage_foundry_archive "${node_zip}" 14.369 "${test_root}/mismatch"
[ ! -e "${test_root}/mismatch/resources/app/main.mjs" ] || fail "mismatch must not stage an app"

node_stage="${test_root}/node-stage"
linux_stage="${test_root}/linux-stage"
assert_equals 14.370 \
  "$(stage_foundry_archive "${node_zip}" 14.370 "${node_stage}")" \
  "node staged version"
assert_equals 14.370 \
  "$(stage_foundry_archive "${linux_zip}" "" "${linux_stage}")" \
  "linux inferred version"

for staged in "${node_stage}" "${linux_stage}"; do
  [ -f "${staged}/resources/app/package.json" ] || fail "missing staged package.json in ${staged}"
  [ -f "${staged}/resources/app/main.mjs" ] || fail "missing staged main.mjs in ${staged}"
done

echo "PASS: archive validation and staging"
