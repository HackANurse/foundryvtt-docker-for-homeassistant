#!/usr/bin/env bash
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-addon-integration.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ruby -ryaml -e '
  config = YAML.load_file(ARGV.fetch(0))
  abort "version" unless config["version"] == "1.2.0"
  abort "target default" unless config.dig("options", "foundry_target_version") == ""
  abort "install default" unless config.dig("options", "install_target_version") == false
  abort "force default" unless config.dig("options", "force_download") == false
  abort "target schema" unless config.dig("schema", "foundry_target_version") == "str?"
  abort "install schema" unless config.dig("schema", "install_target_version") == "bool"
' "${repo_root}/foundryvtt/config.yaml" || fail "add-on configuration is incomplete"

grep -Eq '^COPY (update\.sh|.* update\.sh)' "${repo_root}/foundryvtt/Dockerfile" \
  || fail "Dockerfile does not copy update.sh"
grep -Eq '^COPY (launch\.sh|.* launch\.sh)' "${repo_root}/foundryvtt/Dockerfile" \
  || fail "Dockerfile does not copy launch.sh"
grep -q '^FROM ghcr.io/felddy/foundryvtt:14.370.0$' "${repo_root}/foundryvtt/Dockerfile" \
  || fail "release 1.2.0 does not pin the Foundry 14.370.0 base image"

run_startup_case() {
  case_name="$1"
  install_requested="$2"
  expected_update_calls="$3"
  pending_request="${4:-false}"
  failed_request="${5:-false}"
  force_requested="${6:-false}"
  case_directory="${test_root}/${case_name}"
  config_root="${case_directory}/config"
  foundry_home="${case_directory}/home"
  data_root="${case_directory}/data"
  update_log="${case_directory}/update.log"
  launch_log="${case_directory}/launch.log"
  update_stub="${case_directory}/update-stub.sh"
  launch_stub="${case_directory}/launch-stub.sh"

  mkdir -p "${config_root}/foundry_app/resources/app" "${foundry_home}" "${data_root}"
  printf '{"release":{"generation":14,"build":369}}\n' \
    > "${config_root}/foundry_app/resources/app/package.json"
  printf 'console.log("installed");\n' \
    > "${config_root}/foundry_app/resources/app/main.mjs"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'perform_requested_update() {' \
    '  printf "%s|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4" "$5" >> "${TEST_UPDATE_LOG}"' \
    '}' > "${update_stub}"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" > "${TEST_LAUNCH_LOG}"' > "${launch_stub}"
  chmod 0755 "${update_stub}" "${launch_stub}"

  printf '{"foundry_username":"user","foundry_password":"password","foundry_release_url":"https://example.invalid/release.zip","foundry_target_version":"14.370","install_target_version":%s,"foundry_admin_key":"","foundry_license_key":"","foundry_telemetry":false,"container_preserve_config":true,"force_download":%s}\n' \
    "${install_requested}" "${force_requested}" > "${data_root}/options.json"

  if [ "${pending_request}" = true ]; then
    mkdir -p "${config_root}/.foundry-update"
    printf '{"version":"14.370","fingerprint":"target:14.370"}\n' \
      > "${config_root}/.foundry-update/pending.json"
  fi
  if [ "${failed_request}" = true ]; then
    mkdir -p "${config_root}/.foundry-update"
    printf '{"version":"14.370","fingerprint":"target:14.370","failed":true}\n' \
      > "${config_root}/.foundry-update/failed.json"
  fi

  TEST_UPDATE_LOG="${update_log}" \
  TEST_LAUNCH_LOG="${launch_log}" \
  OPTIONS_PATH="${data_root}/options.json" \
  FOUNDRY_DATA_PATH="${config_root}" \
  FOUNDRY_HOME="${foundry_home}" \
  FOUNDRY_UPDATE_LIB="${update_stub}" \
  FOUNDRY_LAUNCHER="${launch_stub}" \
  FOUNDRY_VERSION=14.369 \
    bash "${repo_root}/foundryvtt/run.sh"

  actual_update_calls=0
  if [ -f "${update_log}" ]; then
    actual_update_calls="$(wc -l < "${update_log}" | tr -d ' ')"
  fi
  [ "${actual_update_calls}" = "${expected_update_calls}" ] \
    || fail "${case_name}: expected ${expected_update_calls} update calls, got ${actual_update_calls}"

  if [ "${expected_update_calls}" = 1 ]; then
    expected_call="14.370|https://example.invalid/release.zip|user|password|${config_root}"
    [ "$(cat "${update_log}")" = "${expected_call}" ] \
      || fail "${case_name}: updater received wrong options"
  fi

  [ -f "${launch_log}" ] || fail "${case_name}: launcher was not invoked"
  grep -q 'entrypoint.sh' "${launch_log}" \
    || fail "${case_name}: launcher did not receive upstream entrypoint"
  grep -q -- '--dataPath=' "${launch_log}" \
    || fail "${case_name}: launcher did not receive the data path"
  [ -f "${config_root}/foundry_app/resources/app/main.mjs" ] \
    || fail "${case_name}: startup removed the installed application"
  if [ "${failed_request}" = true ]; then
    [ ! -e "${config_root}/.foundry-update/failed.json" ] \
      || fail "${case_name}: setting the toggle false did not clear failed state"
  fi
}

run_startup_case disabled false 0 false false false
run_startup_case requested true 1 false false false
run_startup_case pending true 0 true false false
run_startup_case pending-force true 0 true false true
run_startup_case reset-failed false 0 false true false

echo "PASS: add-on configuration and startup integration"
