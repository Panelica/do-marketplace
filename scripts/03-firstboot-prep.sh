#!/bin/bash
# Build-time: install the first-boot secret-regeneration mechanism into the
# snapshot. The rotation script and its systemd unit are uploaded to /tmp by
# Packer's file provisioner; this script places them and enables the unit.
#
# The unit fires once, on the first boot of every Droplet launched from this
# snapshot, regenerating jwt_secret / encryption_key / MySQL root / Redis
# passwords so each customer's Droplet is cryptographically unique. Without
# this, every Droplet cloned from the snapshot would share the build-time
# secrets — a security hole and a Marketplace rejection reason. See
# files/regenerate-secrets.sh for the rationale.
set -euo pipefail

echo "[panelica-build] installing first-boot secret regeneration..."

install -d -m 755 /opt/panelica/scripts/firstboot
install -m 755 /tmp/regenerate-secrets.sh /opt/panelica/scripts/firstboot/regenerate-secrets.sh
install -m 644 /tmp/panelica-firstboot.service /etc/systemd/system/panelica-firstboot.service

# Ensure the "already done" marker is absent so the unit runs on the first
# boot of every Droplet launched from this snapshot.
rm -f /opt/panelica/var/.firstboot-completed

systemctl daemon-reload
systemctl enable panelica-firstboot.service

# Remove the build-time pgAdmin4 database so every Droplet recreates it on its
# first pgAdmin start using the per-instance admin password that
# regenerate-secrets.sh rotates into panelica.conf. If the baked DB shipped,
# pgAdmin's db_upgrade would keep the existing admin@local.dev user and the
# rotated password would never take effect — leaving the shared default in the
# image. pgAdmin is stopped first in case the installer left it running (the
# sqlite file would otherwise be held open / rewritten on shutdown).
systemctl stop panelica-pgadmin4.service 2>/dev/null || true
rm -f /opt/panelica/services/pgadmin4/data/pgadmin4.db
rm -rf /opt/panelica/services/pgadmin4/sessions/* 2>/dev/null || true
echo "[panelica-build] pgAdmin4 DB cleared — recreated per-Droplet on first start"

echo "[panelica-build] first-boot unit installed and enabled"
