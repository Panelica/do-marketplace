#!/bin/bash
# Replace Ubuntu's default MOTD with a Panelica-focused welcome so that
# operators who SSH into a freshly-deployed droplet immediately see the
# panel URL and first-login steps. The DO 1-Click guidelines recommend a
# custom MOTD with the app's hostname/port.
set -euo pipefail

echo "[panelica-build] writing /etc/motd..."

cat > /etc/motd <<'EOF'

   ____   _    _   _ _____ _     ___ ____    _
  |  _ \ / \  | \ | | ____| |   |_ _/ ___|  / \
  | |_) / _ \ |  \| |  _| | |    | | |     / _ \
  |  __/ ___ \| |\  | |___| |___ | | |___ / ___ \
  |_| /_/   \_\_| \_|_____|_____|___\____/_/   \_\

  All-in-one Linux hosting control panel
  --------------------------------------

  Panel UI         https://YOUR_DROPLET_IPV4:8443
  Documentation    https://panelica.com/docs
  Forum & support  https://forum.panelica.com

  FIRST LOGIN
    1. Open the Panel UI in your browser
    2. Accept the self-signed certificate (a real Let's Encrypt
       certificate is issued automatically when you add your
       first domain)
    3. Complete the Setup Wizard to set your root admin password

  PLAN
    Starter tier is free forever for one domain. See
    https://panelica.com/pricing for paid tiers.

EOF

# Ubuntu's dynamic MOTD scripts in /etc/update-motd.d/ would prepend their
# own "Welcome to Ubuntu" banner before ours every login — disable them
# so the Panelica welcome is the first thing the operator sees.
if [ -d /etc/update-motd.d ]; then
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

echo "[panelica-build] motd written"
