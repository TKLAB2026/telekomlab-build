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
  git clone https://github.com/RPi-Distro/pi-gen.git "$WORK_DIR"
fi

# Konfiguration + Custom Stage übernehmen
cp -f "$ROOT_DIR/build/config" "$WORK_DIR/config"
rsync -a "$ROOT_DIR/build/stage-telekomlab/" "$WORK_DIR/stage-telekomlab/"

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