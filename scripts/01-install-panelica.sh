#!/bin/bash
# Install Panelica on the build droplet by calling the same public installer
# every customer uses. Keeping the installer in one place (latest.panelica.com)
# means the DO marketplace snapshot is always shipped from the same code path
# that gets day-to-day testing — no fork, no drift.
set -euo pipefail

echo "[panelica-build] waiting for cloud-init to settle..."
# Cloud-init may still be running apt operations when our provisioner starts;
# racing it produces dpkg-lock errors. Wait up to 5 minutes for it to finish.
cloud-init status --wait || true

echo "[panelica-build] running Panelica installer..."
curl -sSL https://latest.panelica.com/install.sh | bash

# install.sh exits after the 28-step bootstrap completes, but the backend
# spends another ~60s warming caches and rotating logs on first start. Sleep
# briefly so the cleanup step (which truncates /var/log/*) doesn't catch
# the backend mid-write.
echo "[panelica-build] cooldown after install..."
sleep 30

echo "[panelica-build] install complete"
