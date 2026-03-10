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

# Konfiguration + Custom Stage übernehmen
cp -f "$ROOT_DIR/build/config" "$WORK_DIR/config"
rsync -a "$ROOT_DIR/build/stage-telekomlab/" "$WORK_DIR/stage-telekomlab/"

###############################################################################
# PATCHES (wirken auf die frisch geklonte pi-gen-Kopie):

# 1) i386-Basis sicher raus -> amd64 (trifft jede Schreibweise)
sed -i -E \
  's|i386/debian:[A-Za-z0-9._-]+|debian:trixie|g; s|BASE_IMAGE=i386/debian:[A-Za-z0-9._-]+|BASE_IMAGE=debian:trixie|g' \
  "$WORK_DIR/build-docker.sh" || true

# 2) QEMU IM CONTAINER sicher installieren:
#    Einen RUN-Block direkt nach FROM einfügen (nur wenn noch nicht vorhanden)
if ! grep -q 'qemu-user-static' "$WORK_DIR/Dockerfile"; then
  awk '
    BEGIN{added=0}
    /^FROM[[:space:]]/ && added==0 {
      print $0
      print "RUN apt-get -y update && \\"
      print "    apt-get -y install --no-install-recommends qemu-user-static binfmt-support && \\"
      print "    rm -rf /var/lib/apt/lists/*"
      added=1
      next
    }
    {print $0}
  ' "$WORK_DIR/Dockerfile" > "$WORK_DIR/Dockerfile.new" && mv "$WORK_DIR/Dockerfile.new" "$WORK_DIR/Dockerfile"
fi

# 3) HOST-Check deaktivieren (sonst verlangt das Skript qemu-arm auf dem Runner)
#    a) Falls irgendwo hart auf 1 gesetzt wurde -> auf 0 drehen
sed -i -E 's/binfmt_misc_required=1/binfmt_misc_required=0/g' "$WORK_DIR/build-docker.sh" || true
#    b) Die gesamte IF-Bedingung neutralisieren (Block wird komplett übersprungen)
sed -i -E 's/if\s+\[\[\s*"?\$\{?binfmt_misc_required\}?"?\s*==\s*"1"\s*\]\];\s*then/if false; then/g' "$WORK_DIR/build-docker.sh" || true
#    c) Zusätzlich Default auf 0 setzen und Umgebungsvariablen exportieren
sed -i '1a : "${binfmt_misc_required:=0}"' "$WORK_DIR/build-docker.sh" || true
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
``
