#!/usr/bin/env bash
set -Eeuo pipefail

OPTIONS_PATH="/data/options.json"
FOUNDRY_DATA_PATH="/config"
FOUNDRY_CACHE_PATH="${FOUNDRY_DATA_PATH}/container_cache"
FOUNDRY_APP_PATH="${FOUNDRY_DATA_PATH}/foundry_app"
FOUNDRY_RESOURCES_PATH="${FOUNDRY_APP_PATH}/resources"
IMAGE_FOUNDRY_VERSION="${FOUNDRY_VERSION}"

value() {
  jq -r "$1 // empty" "${OPTIONS_PATH}"
}

ensure_symlink() {
  local target="$1"
  local link="$2"

  if [ -L "${link}" ]; then
    ln -sfn "${target}" "${link}"
  elif [ -e "${link}" ]; then
    echo "ATTENZIONE: ${link} esiste e non e un link simbolico; lo lascio invariato."
  else
    ln -s "${target}" "${link}"
  fi
}

FOUNDRY_USERNAME_OPT="$(value '.foundry_username')"
FOUNDRY_PASSWORD_OPT="$(value '.foundry_password')"
FOUNDRY_RELEASE_URL_OPT="$(value '.foundry_release_url')"
FOUNDRY_ADMIN_KEY="$(value '.foundry_admin_key')"
FOUNDRY_LICENSE_KEY="$(value '.foundry_license_key')"
FOUNDRY_TELEMETRY="$(value '.foundry_telemetry')"
CONTAINER_PRESERVE_CONFIG="$(value '.container_preserve_config')"
FORCE_DOWNLOAD="$(value '.force_download')"

export FOUNDRY_ADMIN_KEY
export FOUNDRY_LICENSE_KEY
export FOUNDRY_TELEMETRY
export CONTAINER_PRESERVE_CONFIG
export CONTAINER_CACHE="${FOUNDRY_CACHE_PATH}"
export CONTAINER_CACHE_SIZE="2"

mkdir -p \
  "${FOUNDRY_DATA_PATH}/Backups" \
  "${FOUNDRY_DATA_PATH}/Config" \
  "${FOUNDRY_DATA_PATH}/Data/assets" \
  "${FOUNDRY_DATA_PATH}/Logs" \
  "${FOUNDRY_CACHE_PATH}" \
  "${FOUNDRY_RESOURCES_PATH}"

# Keep the Foundry application itself in addon_config. This is required for
# updates installed from Foundry's web interface to survive an add-on restart.
# If the upstream image already contains Foundry, seed the persistent location
# only on the first start.
if [ ! -f "${FOUNDRY_RESOURCES_PATH}/app/package.json" ] \
  && [ -f /home/node/resources/app/package.json ]; then
  echo "Inizializzo l'installazione persistente di Foundry in ${FOUNDRY_APP_PATH}."
  cp -a /home/node/resources/. "${FOUNDRY_RESOURCES_PATH}/"
fi

# The upstream entrypoint expects resources relative to /home/node. Point that
# path at addon_config so both its installer and Foundry's updater write to
# persistent storage.
rm -rf /home/node/resources
ln -s "${FOUNDRY_RESOURCES_PATH}" /home/node/resources

# The upstream image runs Foundry as node (uid/gid 1000).
chown -R 1000:1000 "${FOUNDRY_DATA_PATH}"
chmod -R u+rwX,g+rwX "${FOUNDRY_DATA_PATH}"

if [ -d /share ]; then
  ensure_symlink /share "${FOUNDRY_DATA_PATH}/Data/assets/haos-share"
fi

if [ -d /media ]; then
  ensure_symlink /media "${FOUNDRY_DATA_PATH}/Data/assets/haos-media"
fi

CACHED_RELEASE="${FOUNDRY_CACHE_PATH}/foundryvtt-${IMAGE_FOUNDRY_VERSION}.zip"
INSTALLED_RELEASE=""

if [ -f "${FOUNDRY_RESOURCES_PATH}/app/package.json" ]; then
  INSTALLED_RELEASE="$(jq -r '.release | "\(.generation).\(.build)"' "${FOUNDRY_RESOURCES_PATH}/app/package.json")"
fi

if [ "${FORCE_DOWNLOAD}" = "true" ]; then
  echo "force_download=true: richiedo un nuovo download di Foundry VTT ${IMAGE_FOUNDRY_VERSION}."
  rm -f "${CACHED_RELEASE}"
  rm -rf "${FOUNDRY_RESOURCES_PATH}"
  mkdir -p "${FOUNDRY_RESOURCES_PATH}"
  chown -R 1000:1000 "${FOUNDRY_APP_PATH}"
  INSTALLED_RELEASE=""
  export FOUNDRY_VERSION="${IMAGE_FOUNDRY_VERSION}"
  export FOUNDRY_USERNAME="${FOUNDRY_USERNAME_OPT}"
  export FOUNDRY_PASSWORD="${FOUNDRY_PASSWORD_OPT}"
  export FOUNDRY_RELEASE_URL="${FOUNDRY_RELEASE_URL_OPT}"
elif [ -n "${INSTALLED_RELEASE}" ]; then
  echo "Foundry ${INSTALLED_RELEASE} e installato nello storage persistente: nessun download richiesto."
  # A web update can be newer than the version baked into the container.
  # Matching FOUNDRY_VERSION prevents the upstream entrypoint from deleting it.
  export FOUNDRY_VERSION="${INSTALLED_RELEASE}"
  unset FOUNDRY_USERNAME FOUNDRY_PASSWORD FOUNDRY_RELEASE_URL
elif [ -f "${CACHED_RELEASE}" ]; then
  echo "Cache Foundry ${IMAGE_FOUNDRY_VERSION} trovata: non uso URL o credenziali per il download."
  export FOUNDRY_VERSION="${IMAGE_FOUNDRY_VERSION}"
  unset FOUNDRY_USERNAME FOUNDRY_PASSWORD FOUNDRY_RELEASE_URL
else
  echo "Cache Foundry ${IMAGE_FOUNDRY_VERSION} assente: abilito il download iniziale."
  export FOUNDRY_VERSION="${IMAGE_FOUNDRY_VERSION}"
  export FOUNDRY_USERNAME="${FOUNDRY_USERNAME_OPT}"
  export FOUNDRY_PASSWORD="${FOUNDRY_PASSWORD_OPT}"
  export FOUNDRY_RELEASE_URL="${FOUNDRY_RELEASE_URL_OPT}"
fi

if [ -z "${INSTALLED_RELEASE}" ] \
  && [ ! -f "${CACHED_RELEASE}" ] \
  && [ -z "${FOUNDRY_RELEASE_URL:-}" ] \
  && { [ -z "${FOUNDRY_USERNAME:-}" ] || [ -z "${FOUNDRY_PASSWORD:-}" ]; }; then
  echo "ERRORE: cache ${IMAGE_FOUNDRY_VERSION} assente. Configura foundry_release_url oppure foundry_username e foundry_password."
  exit 1
fi

echo "Foundry data path: ${FOUNDRY_DATA_PATH}"
echo "Foundry cache path: ${FOUNDRY_CACHE_PATH}"
echo "Foundry application path: ${FOUNDRY_APP_PATH}"
echo "force_download: ${FORCE_DOWNLOAD}"

cd /home/node

exec gosu node:node ./entrypoint.sh \
  resources/app/main.mjs \
  --port=30000 \
  --headless \
  --dataPath="${FOUNDRY_DATA_PATH}"
