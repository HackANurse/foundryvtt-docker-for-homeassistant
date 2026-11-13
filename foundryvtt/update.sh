#!/usr/bin/env bash

# Sourceable helpers for validating and staging Foundry VTT release archives.
# This file intentionally does not change the caller's shell options.

validate_foundry_version() {
  local version="${1:-}"
  [[ "${version}" =~ ^14\.[0-9]+$ ]]
}

archive_foundry_version() {
  local archive="${1:-}"
  local member
  local package_json
  local version

  [ -f "${archive}" ] || return 1

  for member in package.json resources/app/package.json; do
    if package_json="$(unzip -p "${archive}" "${member}" 2>/dev/null)" \
      && [ -n "${package_json}" ]; then
      if version="$(printf '%s' "${package_json}" \
        | jq -r -e '.release | "\(.generation).\(.build)"' 2>/dev/null)" \
        && validate_foundry_version "${version}"; then
        printf '%s\n' "${version}"
        return 0
      fi
    fi
  done

  return 1
}

stage_foundry_archive() {
  local archive="${1:-}"
  local expected_version="${2:-}"
  local destination="${3:-}"
  local found_version
  local destination_parent
  local destination_name
  local staging_directory

  [ -n "${destination}" ] || return 1
  [ ! -e "${destination}" ] || return 1

  found_version="$(archive_foundry_version "${archive}")" || return 1

  if [ -n "${expected_version}" ]; then
    validate_foundry_version "${expected_version}" || return 1
    [ "${found_version}" = "${expected_version}" ] || return 1
  fi

  destination_parent="$(dirname "${destination}")"
  destination_name="$(basename "${destination}")"
  mkdir -p "${destination_parent}"
  staging_directory="$(mktemp -d "${destination_parent}/.${destination_name}.XXXXXX")" \
    || return 1

  if unzip -Z1 "${archive}" 2>/dev/null | grep -qx 'package.json'; then
    mkdir -p "${staging_directory}/resources/app"
    if ! unzip -q "${archive}" -d "${staging_directory}/resources/app"; then
      rm -rf "${staging_directory}"
      return 1
    fi
  elif unzip -Z1 "${archive}" 2>/dev/null | grep -qx 'resources/app/package.json'; then
    if ! unzip -q "${archive}" 'resources/*' -d "${staging_directory}"; then
      rm -rf "${staging_directory}"
      return 1
    fi
  else
    rm -rf "${staging_directory}"
    return 1
  fi

  if [ ! -f "${staging_directory}/resources/app/package.json" ] \
    || [ ! -f "${staging_directory}/resources/app/main.mjs" ]; then
    rm -rf "${staging_directory}"
    return 1
  fi

  if ! mv "${staging_directory}" "${destination}"; then
    rm -rf "${staging_directory}"
    return 1
  fi

  printf '%s\n' "${found_version}"
}

foundry_update_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

installed_foundry_version() {
  local config_root="${1:-}"
  local package_file="${config_root}/foundry_app/resources/app/package.json"
  local version

  [ -f "${package_file}" ] || return 1
  version="$(jq -r -e '.release | "\(.generation).\(.build)"' \
    "${package_file}" 2>/dev/null)" || return 1
  validate_foundry_version "${version}" || return 1
  printf '%s\n' "${version}"
}

foundry_update_fingerprint() {
  local target_version="${1:-}"
  local release_url="${2:-}"

  if [ -n "${target_version}" ]; then
    printf 'target:%s\n' "${target_version}"
  else
    printf 'url:%s\n' "$(printf '%s' "${release_url}" | foundry_update_sha256)"
  fi
}

write_foundry_update_state() {
  local state_file="$1"
  local version="$2"
  local fingerprint="$3"
  local state_directory
  local temporary_state

  state_directory="$(dirname "${state_file}")"
  mkdir -p "${state_directory}"
  temporary_state="$(mktemp "${state_directory}/state.XXXXXX")" || return 1
  if ! jq -n --arg version "${version}" --arg fingerprint "${fingerprint}" \
    '{version: $version, fingerprint: $fingerprint}' > "${temporary_state}"; then
    rm -f "${temporary_state}"
    return 1
  fi
  if ! mv "${temporary_state}" "${state_file}"; then
    rm -f "${temporary_state}"
    return 1
  fi
}

completed_foundry_update_matches() {
  local completed_file="$1"
  local fingerprint="$2"
  local installed_version="$3"
  local completed_fingerprint
  local completed_version

  [ -f "${completed_file}" ] || return 1
  completed_fingerprint="$(jq -r -e '.fingerprint' "${completed_file}" 2>/dev/null)" \
    || return 1
  completed_version="$(jq -r -e '.version' "${completed_file}" 2>/dev/null)" \
    || return 1
  [ "${completed_fingerprint}" = "${fingerprint}" ] \
    && [ "${completed_version}" = "${installed_version}" ]
}

failed_foundry_update_matches() {
  local failed_file="$1"
  local fingerprint="$2"
  local failed_fingerprint

  [ -f "${failed_file}" ] || return 1
  failed_fingerprint="$(jq -r -e '.fingerprint' "${failed_file}" 2>/dev/null)" \
    || return 1
  [ "${failed_fingerprint}" = "${fingerprint}" ]
}

resolve_foundry_release_url() {
  local target_version="$1"
  local username="$2"
  local password="$3"
  local state_directory="$4"
  local update_home="${FOUNDRY_UPDATE_HOME:-/home/node}"
  local node_bin="${FOUNDRY_UPDATE_NODE_BIN:-node}"
  local cookie_file="${state_directory}/cookiejar.json"
  local resolved_url

  [ -n "${target_version}" ] || return 1
  [ -n "${username}" ] && [ -n "${password}" ] || return 1
  [ -f "${update_home}/authenticate.js" ] \
    && [ -f "${update_home}/get_release_url.js" ] || return 1

  rm -f "${cookie_file}"
  if ! "${node_bin}" "${update_home}/authenticate.js" \
    "${username}" "${password}" "${cookie_file}" >/dev/null 2>&1; then
    rm -f "${cookie_file}"
    return 1
  fi

  if ! resolved_url="$("${node_bin}" "${update_home}/get_release_url.js" \
    "${cookie_file}" "${target_version}" 2>/dev/null)" \
    || [ -z "${resolved_url}" ]; then
    rm -f "${cookie_file}"
    return 1
  fi

  rm -f "${cookie_file}"
  printf '%s\n' "${resolved_url}"
}

download_foundry_release() {
  local release_url="$1"
  local destination="$2"
  local error_file="${destination}.error"

  if ! curl --fail --location --silent --show-error \
    --output "${destination}" "${release_url}" 2> "${error_file}"; then
    echo "ERRORE: download della release Foundry non riuscito." >&2
    rm -f "${destination}" "${error_file}"
    return 1
  fi
  rm -f "${error_file}"
}

perform_requested_update() {
  local target_version="${1:-}"
  local release_url="${2:-}"
  local username="${3:-}"
  local password="${4:-}"
  local config_root="${5:-}"
  local state_directory="${config_root}/.foundry-update"
  local completed_file="${state_directory}/completed.json"
  local pending_file="${state_directory}/pending.json"
  local failed_file="${state_directory}/failed.json"
  local live_application="${config_root}/foundry_app"
  local candidate_application="${config_root}/foundry_app.candidate"
  local previous_application="${config_root}/foundry_app.previous"
  local cache_directory="${config_root}/container_cache"
  local request_fingerprint
  local current_version=""
  local effective_url="${release_url}"
  local downloaded_archive
  local found_version
  local cached_archive
  local live_moved=false

  [ -n "${config_root}" ] || return 1
  if [ -z "${target_version}" ] && [ -z "${release_url}" ]; then
    echo "ERRORE: specifica foundry_target_version oppure foundry_release_url." >&2
    return 1
  fi
  if [ -n "${target_version}" ]; then
    validate_foundry_version "${target_version}" || {
      echo "ERRORE: foundry_target_version deve avere formato 14.<build>." >&2
      return 1
    }
  fi

  request_fingerprint="$(foundry_update_fingerprint \
    "${target_version}" "${release_url}")" || return 1
  current_version="$(installed_foundry_version "${config_root}" 2>/dev/null || true)"

  if [ -z "${current_version}" ]; then
    echo "ERRORE: completa prima l'installazione iniziale di Foundry; l'aggiornamento manuale richiede una versione da ripristinare." >&2
    return 1
  fi

  if [ -n "${target_version}" ] && [ "${current_version}" = "${target_version}" ]; then
    write_foundry_update_state "${completed_file}" \
      "${current_version}" "${request_fingerprint}"
    echo "Foundry ${current_version} e gia installato: aggiornamento non necessario."
    return 0
  fi
  if [ -n "${current_version}" ] \
    && completed_foundry_update_matches "${completed_file}" \
      "${request_fingerprint}" "${current_version}"; then
    echo "Richiesta di aggiornamento gia completata per Foundry ${current_version}."
    return 0
  fi
  if failed_foundry_update_matches "${failed_file}" "${request_fingerprint}"; then
    echo "ATTENZIONE: questa richiesta e gia fallita; avvio la versione ripristinata. Imposta install_target_version su false prima di riprovare." >&2
    return 0
  fi

  [ ! -e "${previous_application}" ] || {
    echo "ERRORE: esiste gia una copia di rollback; aggiornamento annullato." >&2
    return 1
  }

  mkdir -p "${state_directory}" "${cache_directory}"
  if [ -z "${effective_url}" ]; then
    effective_url="$(resolve_foundry_release_url "${target_version}" \
      "${username}" "${password}" "${state_directory}")" || {
      echo "ERRORE: impossibile ottenere l'URL della release richiesta." >&2
      return 1
    }
  fi

  downloaded_archive="$(mktemp "${cache_directory}/manual-update.XXXXXX")" \
    || return 1
  if ! download_foundry_release "${effective_url}" "${downloaded_archive}"; then
    return 1
  fi

  rm -rf "${candidate_application}"
  if ! found_version="$(stage_foundry_archive "${downloaded_archive}" \
    "${target_version}" "${candidate_application}")"; then
    echo "ERRORE: archivio Foundry non valido o versione non corrispondente." >&2
    rm -f "${downloaded_archive}"
    rm -rf "${candidate_application}"
    return 1
  fi

  if [ "$(id -u)" -eq 0 ]; then
    chown -R 1000:1000 "${candidate_application}"
  fi

  cached_archive="${cache_directory}/foundryvtt-${found_version}.zip"
  if ! mv -f "${downloaded_archive}" "${cached_archive}"; then
    rm -f "${downloaded_archive}"
    rm -rf "${candidate_application}"
    return 1
  fi

  if [ -e "${live_application}" ]; then
    if ! mv "${live_application}" "${previous_application}"; then
      rm -rf "${candidate_application}"
      return 1
    fi
    live_moved=true
  fi

  if ! mv "${candidate_application}" "${live_application}"; then
    if [ "${live_moved}" = true ]; then
      mv "${previous_application}" "${live_application}" || true
    fi
    rm -rf "${candidate_application}"
    return 1
  fi

  if ! write_foundry_update_state "${pending_file}" \
    "${found_version}" "${request_fingerprint}"; then
    rm -rf "${live_application}"
    if [ "${live_moved}" = true ]; then
      mv "${previous_application}" "${live_application}" || true
    fi
    return 1
  fi

  echo "Foundry ${found_version} preparato; il primo avvio confermera l'aggiornamento."
}

confirm_pending_update() {
  local config_root="${1:-}"
  local state_directory="${config_root}/.foundry-update"
  local pending_file="${state_directory}/pending.json"
  local completed_file="${state_directory}/completed.json"
  local previous_application="${config_root}/foundry_app.previous"

  [ -f "${pending_file}" ] || return 1
  jq -e '.version and .fingerprint' "${pending_file}" >/dev/null 2>&1 \
    || return 1
  [ ! -d "${completed_file}" ] || return 1

  mv "${pending_file}" "${completed_file}" || return 1
  if ! rm -rf "${previous_application}"; then
    mv "${completed_file}" "${pending_file}" || true
    return 1
  fi
  rm -f "${state_directory}/failed.json"
}

rollback_pending_update() {
  local config_root="${1:-}"
  local state_directory="${config_root}/.foundry-update"
  local pending_file="${state_directory}/pending.json"
  local failed_file="${state_directory}/failed.json"
  local live_application="${config_root}/foundry_app"
  local previous_application="${config_root}/foundry_app.previous"
  local failed_temporary

  [ -f "${pending_file}" ] || return 1
  mkdir -p "${state_directory}"
  failed_temporary="$(mktemp "${state_directory}/failed.XXXXXX")" || return 1
  if ! jq '. + {failed: true}' "${pending_file}" > "${failed_temporary}"; then
    rm -f "${failed_temporary}"
    return 1
  fi

  rm -rf "${live_application}"
  if [ -e "${previous_application}" ]; then
    if ! mv "${previous_application}" "${live_application}"; then
      rm -f "${failed_temporary}"
      return 1
    fi
  fi

  mv "${failed_temporary}" "${failed_file}"
  rm -f "${pending_file}"
}
