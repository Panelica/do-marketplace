#!/bin/bash
# Panelica Hosting Panel — DigitalOcean Marketplace 1-Click installer.
# Runs once on the build Droplet (Ubuntu 24.04). Installs Panelica from the same
# public installer every customer uses (latest.panelica.com — no fork, no drift),
# then wires the per-Droplet first-boot secret + IP rotation so every Droplet
# cloned from the snapshot is cryptographically unique.
set -euo pipefail

echo "[panelica-build] waiting for cloud-init to settle..."
cloud-init status --wait || true

echo "[panelica-build] installing Panelica (latest.panelica.com)..."
curl -sSL https://latest.panelica.com/install.sh | bash

# install.sh returns after the bootstrap; the backend warms caches/rotates logs
# for ~60s on first start. Brief cooldown so cleanup doesn't catch it mid-write.
echo "[panelica-build] cooldown after install..."
sleep 30

# --- Per-Droplet first-boot secret + IP rotation -----------------------------
# Without this every Droplet cloned from the snapshot would share the build-time
# jwt_secret / encryption_key / MySQL / Redis / pgAdmin passwords AND the build
# Droplet's IP — a security hole and a Marketplace rejection reason. The systemd
# oneshot runs once, before panelica-backend, regenerating them per Droplet.
echo "[panelica-build] installing first-boot secret + IP rotation..."
install -d -m 755 /opt/panelica/scripts/firstboot
install -m 755 /var/lib/digitalocean/regenerate-secrets.sh /opt/panelica/scripts/firstboot/regenerate-secrets.sh
install -m 644 /var/lib/digitalocean/panelica-firstboot.service /etc/systemd/system/panelica-firstboot.service
# Ensure the "already done" marker is absent so the unit runs on every Droplet's
# first boot.
rm -f /opt/panelica/var/.firstboot-completed
systemctl daemon-reload
systemctl enable panelica-firstboot.service

# Remove the baked pgAdmin DB so each Droplet recreates it on first pgAdmin start
# with the per-instance password rotated by regenerate-secrets.sh. If the baked
# DB shipped, db_upgrade would keep the existing admin user and the rotated
# password would never take effect. Stop pgAdmin first in case it is running.
systemctl stop panelica-pgadmin4.service 2>/dev/null || true
rm -f /opt/panelica/services/pgadmin4/data/pgadmin4.db
rm -rf /opt/panelica/services/pgadmin4/sessions/* 2>/dev/null || true

# The staged /var/lib/digitalocean copies are no longer needed in the snapshot.
rm -f /var/lib/digitalocean/regenerate-secrets.sh /var/lib/digitalocean/panelica-firstboot.service

echo "[panelica-build] install complete"
