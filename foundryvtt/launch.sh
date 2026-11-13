#!/usr/bin/env bash
set -u

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
FOUNDRY_DATA_PATH="${FOUNDRY_DATA_PATH:-/config}"
FOUNDRY_HEALTH_HOST="${FOUNDRY_HEALTH_HOST:-127.0.0.1}"
FOUNDRY_HEALTH_PORT="${FOUNDRY_HEALTH_PORT:-30000}"
FOUNDRY_HEALTH_TIMEOUT="${FOUNDRY_HEALTH_TIMEOUT:-180}"
FOUNDRY_HEALTH_INTERVAL="${FOUNDRY_HEALTH_INTERVAL:-1}"
UPDATE_LIBRARY="${FOUNDRY_UPDATE_LIB:-${SCRIPT_DIRECTORY}/update.sh}"
PENDING_FILE="${FOUNDRY_DATA_PATH}/.foundry-update/pending.json"

# shellcheck source=update.sh
. "${UPDATE_LIBRARY}"

if [ "$#" -eq 0 ]; then
  echo "ERRORE: comando Foundry mancante." >&2
  exit 2
fi

child_pid=""
signal_forwarded=false

forward_signal() {
  local signal_name="$1"
  if [ "${signal_forwarded}" = false ] \
    && [ -n "${child_pid}" ] \
    && kill -0 "${child_pid}" 2>/dev/null; then
    signal_forwarded=true
    kill -"${signal_name}" "${child_pid}" 2>/dev/null || true
  fi
}

wait_for_foundry_child() {
  local wait_status
  while :; do
    wait "${child_pid}"
    wait_status=$?
    if ! kill -0 "${child_pid}" 2>/dev/null; then
      return "${wait_status}"
    fi
  done
}

foundry_port_is_ready() {
  (printf '\n' > "/dev/tcp/${FOUNDRY_HEALTH_HOST}/${FOUNDRY_HEALTH_PORT}") \
    >/dev/null 2>&1
}

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

"$@" &
child_pid=$!

if [ -f "${PENDING_FILE}" ]; then
  deadline=$((SECONDS + FOUNDRY_HEALTH_TIMEOUT))
  while :; do
    if foundry_port_is_ready; then
      if ! confirm_pending_update "${FOUNDRY_DATA_PATH}"; then
        echo "ERRORE: impossibile confermare l'aggiornamento Foundry." >&2
        forward_signal TERM
        wait_for_foundry_child >/dev/null 2>&1 || true
        rollback_pending_update "${FOUNDRY_DATA_PATH}" || true
        exit 1
      fi
      echo "Aggiornamento Foundry confermato dopo il controllo di avvio."
      break
    fi

    if ! kill -0 "${child_pid}" 2>/dev/null; then
      wait "${child_pid}"
      child_status=$?
      rollback_pending_update "${FOUNDRY_DATA_PATH}" || true
      echo "ERRORE: il nuovo Foundry e terminato prima del controllo di avvio." >&2
      if [ "${child_status}" -eq 0 ]; then
        child_status=1
      fi
      exit "${child_status}"
    fi

    if [ "${SECONDS}" -ge "${deadline}" ]; then
      echo "ERRORE: il nuovo Foundry non ha aperto la porta entro ${FOUNDRY_HEALTH_TIMEOUT}s." >&2
      forward_signal TERM
      wait_for_foundry_child >/dev/null 2>&1 || true
      rollback_pending_update "${FOUNDRY_DATA_PATH}" || true
      exit 1
    fi

    sleep "${FOUNDRY_HEALTH_INTERVAL}"
  done
fi

wait_for_foundry_child
exit $?
