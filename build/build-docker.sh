#!/usr/bin/env bash
# ==== stabile Defaults, verhindern "unbound variable" ====
: "${binfmt_misc_required:=0}"        # 0 = Host-BINFMT NICHT nötig
: "${DOCKER_CMDLINE_PRE:=}"
: "${DOCKER_CMDLINE_POST:=}"
: "${DOCKER_CMDLINE_NAME:=pigen_work}"   # Containername-Default
: "${PRESERVE_CONTAINER:=0}"
: "${CONTINUE:=0}"
: "${PIGEN_DOCKER_OPTS:=}"

set -eu

# Arbeitsverzeichnis (= Ordner, in dem diese Datei liegt)
DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BUILD_OPTS="${*}"

# Docker-Binary festlegen (rootless vermeiden)
DOCKER=${DOCKER:-docker}
if ! ${DOCKER} ps >/dev/null 2>&1 && ${DOCKER} info 2>/dev/null | grep -q rootless; then
  DOCKER="sudo ${DOCKER}"
fi
if ! ${DOCKER} ps >/dev/null 2>&1; then
  echo "error connecting to docker:"
  ${DOCKER} ps || true
  exit 1
fi

# Konfigurationsdatei ermitteln und einlesen
CONFIG_FILE=""
if [ -f "${DIR}/config" ]; then
  CONFIG_FILE="${DIR}/config"
fi
while getopts "c:" flag; do
  case "${flag}" in
    c) CONFIG_FILE="${OPTARG}" ;;
    *) ;;
  esac
done
if command -v realpath >/dev/null 2>&1 && [ -n "${CONFIG_FILE}" ]; then
  CONFIG_FILE="$(realpath -s "${CONFIG_FILE}" || realpath "${CONFIG_FILE}")"
fi
if [ -z "${CONFIG_FILE}" ]; then
  echo "Configuration file missing. Provide ${DIR}/config or pass -c <path>."
  exit 1
else
  # shellcheck disable=SC1090
  . "${CONFIG_FILE}"
fi

# Pflicht-Variable aus config: IMG_NAME
if [ -z "${IMG_NAME:-}" ]; then
  echo "IMG_NAME not set in config" >&2
  exit 1
fi

# Container vorhanden/aktiv?
CONTAINER_NAME="${DOCKER_CMDLINE_NAME}"
CONTAINER_EXISTS="$(${DOCKER} ps -a --filter name="${CONTAINER_NAME}" -q)"
CONTAINER_RUNNING="$(${DOCKER} ps --filter name="${CONTAINER_NAME}" -q)"
if [ -n "${CONTAINER_RUNNING}" ]; then
  echo "Build already running in ${CONTAINER_NAME}. Aborting."
  exit 1
fi
if [ -n "${CONTAINER_EXISTS}" ] && [ "${CONTINUE}" != "1" ]; then
  echo "Container ${CONTAINER_NAME} exists. Set CONTINUE=1 or remove it:"
  echo "  ${DOCKER} rm -v ${CONTAINER_NAME}"
  exit 1
fi

# ggf. -c <pfad> im BUILD_OPTS auf /config umschreiben (im Container)
BUILD_OPTS="$(echo "${BUILD_OPTS:-}" | sed -E 's@-c\s?([^ ]+)@-c /config@g')"

# ===== Basis-Image korrekt wählen (KEIN i386!) =====
case "$(uname -m)" in
  x86_64|aarch64)
    BASE_IMAGE="${BASE_IMAGE:-debian:trixie}"
    ;;
  *)
    BASE_IMAGE="${BASE_IMAGE:-debian:trixie}"
    ;;
esac

# ===== Host-BINFMT prüfen (nur wenn ausdrücklich gefordert) =====
if [ "${binfmt_misc_required}" = "1" ] && [ "${SKIP_BINFMT:-0}" != "1" ]; then
  if ! command -v qemu-arm >/dev/null 2>&1; then
    echo "qemu-arm not found (please install qemu-user-binfmt)"; exit 1
  fi
  if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
    echo "binfmt_misc not mounted, trying to mount..."
    mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc || { echo "mount failed"; exit 1; }
  fi
fi

# ===== pi-gen Image bauen (ohne Cache), mit passendem BASE_IMAGE =====
${DOCKER} build --no-cache --build-arg BASE_IMAGE="${BASE_IMAGE}" -t pi-gen "${DIR}"

# ===== Build im Container ausführen =====
trap 'echo "CTRL+C... stopping ${CONTAINER_NAME} in 5s"; ${DOCKER} stop -t 5 ${CONTAINER_NAME} || true' SIGINT SIGTERM

time ${DOCKER} run \
  ${DOCKER_CMDLINE_PRE} \
  --name "${CONTAINER_NAME}" \
  --privileged \
  ${PIGEN_DOCKER_OPTS} \
  --volume "${CONFIG_FILE}":/config:ro \
  -e "GIT_HASH=${GIT_HASH:-$(git -C "${DIR}" rev-parse HEAD 2>/dev/null || echo unknown)}" \
  ${DOCKER_CMDLINE_POST} \
  pi-gen \
  bash -e -o pipefail -c "
    (mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc || true)
    cd /pi-gen
    ./build.sh ${BUILD_OPTS}
    rsync -av work/*/build.log deploy/ || true
  " &

wait "$!"

echo "copying results from deploy/"
${DOCKER} cp "${CONTAINER_NAME}":/pi-gen/deploy - | tar -xf -

echo "copying docker log to deploy/build-docker.log"
${DOCKER} logs --timestamps "${CONTAINER_NAME}" &>deploy/build-docker.log || true

ls -lah deploy || true

if [ "${PRESERVE_CONTAINER}" != "1" ]; then
  ${DOCKER} rm -v "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo "Done! Your image(s) should be in deploy/"