#!/bin/bash
# DigitalOcean Marketplace image validation — runs AFTER cleanup so it
# validates the final, cleaned snapshot state (SSH keys removed, logs
# truncated, history cleared). We pull the validator straight from the
# official partner repo so we always run the exact same check DigitalOcean's
# reviewers run against our snapshot.
#
#   99-img-check.sh exit codes (verified 2026-06-24):
#     0  = all PASS, or only non-critical WARNINGS  -> build continues
#     1  = a critical test FAILED, or unsupported OS -> build ABORTS
#
# `set -o errexit` makes a FAIL exit-code abort the Packer build immediately,
# so a non-compliant image never reaches the snapshot step.
set -o errexit

VALIDATOR_URL="https://raw.githubusercontent.com/digitalocean/marketplace-partners/master/scripts/99-img-check.sh"
WORK="/tmp/img-check"

echo "[panelica-build] downloading official DigitalOcean image validator..."
mkdir -p "${WORK}"
curl -sSL "${VALIDATOR_URL}" -o "${WORK}/99-img-check.sh"
chmod +x "${WORK}/99-img-check.sh"

echo "[panelica-build] running img-check (non-interactive, no args)..."
# Exit code propagates under set -e: WARN(0) lets the build pass, FAIL(1) aborts.
"${WORK}/99-img-check.sh"

echo "[panelica-build] img-check passed (0 critical failures) — cleaning validator..."
# Leave nothing behind in the snapshot: remove the downloaded validator and
# re-clear /tmp so the image stays pristine after validation.
rm -rf "${WORK}"
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

echo "[panelica-build] validation complete — image is marketplace-ready"
