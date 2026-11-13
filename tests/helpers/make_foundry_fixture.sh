#!/usr/bin/env bash
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 OUTPUT VERSION node|linux" >&2
  exit 2
fi

output="$1"
version="$2"
layout="$3"
generation="${version%%.*}"
build="${version#*.}"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-fixture.XXXXXX")"

trap 'rm -rf "${fixture_root}"' EXIT INT TERM

case "${layout}" in
  node)
    app_root="${fixture_root}"
    ;;
  linux)
    app_root="${fixture_root}/resources/app"
    ;;
  *)
    echo "unknown layout: ${layout}" >&2
    exit 2
    ;;
esac

mkdir -p "${app_root}"
printf '{"release":{"generation":%s,"build":%s}}\n' \
  "${generation}" "${build}" > "${app_root}/package.json"
printf 'console.log("fixture");\n' > "${app_root}/main.mjs"

mkdir -p "$(dirname "${output}")"
output="$(cd "$(dirname "${output}")" && pwd)/$(basename "${output}")"
(
  cd "${fixture_root}"
  zip -qr "${output}" .
)
