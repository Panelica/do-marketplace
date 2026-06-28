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

echo "[panelica-build] first-boot unit installed and enabled"
