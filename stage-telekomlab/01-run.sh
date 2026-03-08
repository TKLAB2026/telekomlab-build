#!/usr/bin/env bash
set -e

# Copy files into rootfs is handled by pi-gen automatically when present under 'files/'.
# Here we ensure ownerships and enable services.

on_chroot << 'EOF'
set -e
# Asterisk beim Boot starten
systemctl enable asterisk || true
# Eigentümer für Lehrer-Doku setzen
chown -R pi:pi /home/pi/telekomlab || true
EOF
