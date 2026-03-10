#!/usr/bin/env bash
set -euo pipefail

# Basis-Pfade
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/pi-gen"
OUTPUT_DIR="$ROOT_DIR/output"

mkdir -p "$OUTPUT_DIR"

# pi-gen bei Bedarf klonen
if [ ! -d "$WORK_DIR" ]; then
  echo "Cloning pi-gen..."
  git clone --branch bookworm https://github.com/RPi-Distro/pi-gen.git "$WORK_DIR"
fi

###############################################################################
# FIX: Kombinierter Archiv-Keyring für Stage0 (behebt "unknown key .../Invalid Release signature")

sudo apt-get update -y
sudo apt-get install -y gnupg ca-certificates curl

TMPKEY="$WORK_DIR/stage0/files/pi-keys.asc"

# 1) Raspbian (raspbian.raspberrypi.org) – offizieller Public Key (Fingerprint endet u.a. auf 90FDDD2E)
curl -fsSL https://archive.raspbian.org/raspbian.public.key >> "$TMPKEY"

# 2) Raspberry Pi Archive (archive.raspberrypi.org) – offizieller Archiv-Key
curl -fsSL http://archive.raspberrypi.org/debian/raspberrypi.gpg.key >> "$TMPKEY"

# 3) Debian 12 (Bookworm) – offizieller Debian-Archiv-Key
curl -fsSL https://ftp-master.debian.org/keys/archive-key-12.asc >> "$TMPKEY"

# In einen gemeinsamen GPG-Keyring umwandeln, den debootstrap versteht:
gpg --dearmor < "$TMPKEY" > "$WORK_DIR/stage0/files/raspberrypi.gpg"
rm -f "$TMPKEY"
###############################################################################


# Konfiguration + Custom Stage übernehmen
cp -f "$ROOT_DIR/build/config" "$WORK_DIR/config"
rsync -a "$ROOT_DIR/build/stage-telekomlab/" "$WORK_DIR/stage-telekomlab/"

###############################################################################
# Zusätzliche Patches (harmlos, aber wichtig)

# 1) i386 raus
sed -i -E \
  's|i386/debian:[A-Za-z0-9._-]+|debian:bookworm|g; s|BASE_IMAGE=i386/debian:[A-Za-z0-9._-]+|BASE_IMAGE=debian:bookworm|g' \
  "$WORK_DIR/build-docker.sh" || true

# 2) QEMU im Container installieren
if ! grep -q 'qemu-user-static' "$WORK_DIR/Dockerfile"; then
  awk '
    BEGIN{added=0}
    /^FROM[[:space:]]/ && added==0 {
      print $0
      print "RUN apt-get update -y && apt-get install -y --no-install-recommends qemu-user-static binfmt-support && rm -rf /var/lib/apt/lists/*"
      added=1
      next
    }
    {print $0}
  ' "$WORK_DIR/Dockerfile" > "$WORK_DIR/Dockerfile.new" && mv "$WORK_DIR/Dockerfile.new" "$WORK_DIR/Dockerfile"
fi

# 3) HOST-Check deaktivieren (wichtiger Fix)
sed -i -E 's/binfmt_misc_required=1/binfmt_misc_required=0/g' "$WORK_DIR/build-docker.sh" || true
sed -i -E 's/\[\[\s*"\$\{?binfmt_misc_required\}?"\s*==\s*"1"\s*\]\]/false/g' "$WORK_DIR/build-docker.sh" || true
export binfmt_misc_required=0
export SKIP_BINFMT=1
###############################################################################

# Build-Parameter
export CONTINUE=1
export DEPLOY_ZIP=1
export IMG_NAME="telekomlab"
export STAGE_LIST="stage0 stage1 stage2 stage3 stage-telekomlab"

# Build im pi-gen starten (Docker-Variante)
cd "$WORK_DIR"
./build-docker.sh

# Ergebnisse ins output/-Verzeichnis einsammeln
mkdir -p "$OUTPUT_DIR"
if ls deploy/*.zip >/dev/null 2>&1; then
  mv deploy/*.zip "$OUTPUT_DIR"/
fi
if ls deploy/*.img >/dev/null 2>&1; then
  mv deploy/*.img "$OUTPUT_DIR"/
fi

echo
echo "Build abgeschlossen. Dateien liegen in: $OUTPUT_DIR"
