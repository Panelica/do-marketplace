#!/bin/bash
# DigitalOcean Marketplace mandatory cleanup. This is a near-verbatim copy
# of the official cleanup.sh from
#   https://github.com/digitalocean/marketplace-partners/blob/master/scripts/90-cleanup.sh
# Keeping it close to the upstream copy means the DigitalOcean reviewers
# running img-check.sh against our snapshot will see exactly the cleanup
# pattern they expect.
#
# Why each step matters (img-check.sh failure prevention):
#   - update + upgrade: ensures the snapshot ships current security patches
#   - clear /tmp, history, logs: prevents leaking PII / install secrets
#   - remove /root/.ssh keys and /etc/ssh host keys: every droplet spawned
#     from the snapshot gets fresh keys via cloud-init (this is *the*
#     non-negotiable rule of marketplace snapshots — fail this, get banned)
#   - zero-fill the free space: secure-erases any deleted-but-recoverable
#     data so disk forensics on a duplicated snapshot can't recover it
set -o errexit

# Some marketplace partner builds have hit a missing /tmp issue (cloud-init
# can race against tmpfs mount). Be defensive.
if [[ ! -d /tmp ]]; then
    mkdir /tmp
fi
chmod 1777 /tmp

echo "[panelica-build] updating + upgrading packages..."
if [ -n "$(command -v yum)" ]; then
    yum update -y
    yum clean all
elif [ -n "$(command -v apt-get)" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    apt-get -o Dpkg::Options::="--force-confold" upgrade -q -y --force-yes
    apt-get -y autoremove
    apt-get -y autoclean
fi

echo "[panelica-build] removing DigitalOcean monitoring agent (base-image)..."
# The DigitalOcean ubuntu-24-04 base image ships the do-agent monitoring
# package, which lives in /opt/digitalocean. img-check.sh treats the presence
# of that directory as a CRITICAL FAIL (verified 2026-06-28 build: "[FAIL]
# DigitalOcean directory detected") because each customer Droplet installs its
# own agent when monitoring is enabled — it must not be baked into a snapshot.
# Purge the package and remove the directory unconditionally so STATUS drops
# from 2 (FAIL→abort) to at most 1 (WARN→pass).
if [ -n "$(command -v apt-get)" ]; then
    apt-get -y purge do-agent 2>/dev/null || true
    apt-get -y autoremove 2>/dev/null || true
fi
rm -rf /opt/digitalocean

echo "[panelica-build] clearing crash reports (reduces img-check WARN)..."
# apport caught a transient fail2ban-server restart during install and wrote a
# crash report; clear it so the validator's "un-cleared log" WARN list shrinks.
rm -rf /var/crash/* 2>/dev/null || true

echo "[panelica-build] clearing /tmp, bash history, /var/log..."
rm -rf /tmp/* /var/tmp/*
history -c
cat /dev/null > /root/.bash_history
unset HISTFILE
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????

echo "[panelica-build] clearing cloud-init instance state..."
rm -rf /var/lib/cloud/instances/*

echo "[panelica-build] removing build-droplet SSH keys..."
rm -f /root/.ssh/authorized_keys
rm -f /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

echo "[panelica-build] secure-erasing free disk space (this can take several minutes)..."
# dd will fail with "No space left on device" when complete — that's the
# expected behaviour, hence the `|| rm /zerofile` fallback so we don't
# leave a multi-gigabyte zerofile behind in the snapshot.
dd if=/dev/zero of=/zerofile bs=4096 || rm -f /zerofile
sync

echo "[panelica-build] cleanup complete — snapshot ready"
