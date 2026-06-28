#!/bin/bash
# Panelica marketplace image — first-boot secret regeneration.
#
# WHY: the snapshot is baked with secrets (jwt_secret, encryption_key, the
# MySQL root password and the Redis password) generated once at build time.
# Without rotation, every Droplet launched from the snapshot would share them —
# a cross-instance security hole (token forgery, decryptable data at rest) and
# a Marketplace rejection ("hardcoded/shared secrets in the image").
#
# WHEN: the systemd oneshot panelica-firstboot.service runs this once, on the
# first boot, after panelica-mysql/redis are up and BEFORE panelica-backend
# starts — so the backend reads the fresh secrets on its very first start.
#
# SAFETY: the snapshot ships in Setup Wizard state — no domains, databases, FTP
# accounts or stored customer secrets exist yet — so nothing is encrypted with
# the old encryption_key and rotating it here cannot orphan any data.
#
# Note: no `set -e`. The jwt/encryption rotation is independent of the MySQL
# and Redis rotation; one step failing must not abort the others. Each step
# verifies itself and, on failure, leaves that secret unchanged (still working,
# just not rotated) rather than bricking the panel.
set -u

INSTALL_DIR=/opt/panelica
CONF="${INSTALL_DIR}/panelica.conf"
MARKER="${INSTALL_DIR}/var/.firstboot-completed"
REDIS_CONF="${INSTALL_DIR}/etc/redis/redis.conf"
MYSQL_SOCK="${INSTALL_DIR}/var/run/mysqld/mysqld.sock"
MYSQL="${INSTALL_DIR}/services/mysql/bin/mysql"
LOG=/var/log/panelica-firstboot.log

exec >>"$LOG" 2>&1
echo "=================================================="
echo "panelica-firstboot  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Idempotency — run exactly once per instance.
if [ -f "$MARKER" ]; then
    echo "marker exists — secrets already rotated, nothing to do"
    exit 0
fi

# Same generation recipe as the installer (alphanumeric only — safe to drop
# verbatim into the ini file and into SQL/Redis config).
gen() { openssl rand -base64 "$1" | tr -d '/+=\n' | head -c "$2"; }

# Section-aware read of panelica.conf (a plain ini file). The key `password`
# exists under three sections, so naive grep/sed is wrong — match the section.
conf_get() {  # conf_get <section> <key>
    awk -v sec="[$1]" -v k="$2" '
        /^\[.*\]/ { cur=$0; next }
        cur==sec && $0 ~ "^"k"[ \t]*=" { sub(/^[^=]*=[ \t]*/,""); print; exit }
    ' "$CONF"
}

conf_set() {  # conf_set <section> <key> <value>
    local sec="[$1]" k="$2" v="$3" tmp
    tmp=$(mktemp)
    awk -v sec="$sec" -v k="$k" -v v="$v" '
        /^\[.*\]/ { cur=$0 }
        { if (cur==sec && $0 ~ "^"k"[ \t]*=") { print k " = " v; next } print }
    ' "$CONF" > "$tmp" && cat "$tmp" > "$CONF"
    rm -f "$tmp"
}

# Wait until the MySQL socket actually exists (After= only orders unit start,
# not readiness).
for i in $(seq 1 30); do
    [ -S "$MYSQL_SOCK" ] && break
    echo "waiting for MySQL socket ($i/30)..."
    sleep 2
done

# --- 1. JWT secret + encryption key ----------------------------------------
# Config-only: panelica-backend has not started yet (systemd ordering), so it
# will read these fresh on its first start. No restart needed.
NEW_JWT=$(gen 64 64)
NEW_ENC=$(openssl rand -hex 32 | head -c 64)
if [ -n "$NEW_JWT" ] && [ -n "$NEW_ENC" ]; then
    conf_set security jwt_secret "$NEW_JWT"
    conf_set security encryption_key "$NEW_ENC"
    echo "OK    security.jwt_secret + security.encryption_key rotated"
else
    echo "ERROR could not generate jwt/encryption key — left unchanged"
fi

# --- 2. Redis password ------------------------------------------------------
NEW_REDIS=$(gen 32 32)
if [ -n "$NEW_REDIS" ] && [ -f "$REDIS_CONF" ]; then
    if grep -q '^requirepass' "$REDIS_CONF"; then
        sed -i "s|^requirepass .*|requirepass ${NEW_REDIS}|" "$REDIS_CONF"
    else
        echo "requirepass ${NEW_REDIS}" >> "$REDIS_CONF"
    fi
    conf_set cache.redis password "$NEW_REDIS"
    systemctl restart panelica-redis.service
    sleep 2
    if systemctl is-active --quiet panelica-redis.service; then
        echo "OK    cache.redis password rotated + service restarted"
    else
        echo "ERROR panelica-redis not active after restart"
    fi
else
    echo "ERROR redis config missing or keygen failed — left unchanged"
fi

# --- 3. MySQL root password -------------------------------------------------
OLD_MYSQL=$(conf_get database.mysql password)
NEW_MYSQL=$(gen 32 32)
if [ -n "$OLD_MYSQL" ] && [ -n "$NEW_MYSQL" ] && [ -x "$MYSQL" ]; then
    if "$MYSQL" -u root -p"$OLD_MYSQL" -S "$MYSQL_SOCK" \
         -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_MYSQL}'; FLUSH PRIVILEGES;"; then
        conf_set database.mysql password "$NEW_MYSQL"
        if "$MYSQL" -u root -p"$NEW_MYSQL" -S "$MYSQL_SOCK" -e "SELECT 1;" >/dev/null 2>&1; then
            echo "OK    database.mysql root password rotated + verified"
        else
            echo "ERROR MySQL verify with new password failed"
        fi
    else
        echo "ERROR MySQL ALTER USER failed — password left unchanged"
    fi
else
    echo "ERROR MySQL client or old password missing — left unchanged"
fi

# NOTE: this script must NOT `systemctl restart` other panelica services.
# panelica-bandwidth-limiter is ordered After=panelica-backend, and backend is
# ordered After=panelica-firstboot — so a restart call here blocks on a job
# that cannot run until this script finishes: a circular deadlock. Every
# secret-consuming daemon (backend, external-api, bandwidth, ...) is instead
# ordered After this unit via Before= in panelica-firstboot.service, so they
# start fresh once this script exits. Restarting Redis above is safe — Redis
# is upstream of this unit (After=panelica-redis), not downstream.

# --- 3.5 pgAdmin4 admin password -------------------------------------------
# The build deleted the baked pgadmin4.db (see scripts/03-firstboot-prep.sh),
# so pgAdmin (re)creates its DB on its first start from PGADMIN_SETUP_PASSWORD,
# which start_pgadmin.sh exports from this key. Rotating it here — before
# panelica-pgadmin4 starts (Before= ordering) — gives every Droplet a unique
# pgAdmin login instead of the default shipped in the image. Config-only, no
# service touch: pgAdmin is ordered After this unit, and the DB is absent until
# then, so the rotated password is the one baked into the new DB.
# (If the baked DB had shipped, db_upgrade would keep the old admin user and
# this rotation would never take effect — hence the build-time DB deletion.)
NEW_PGADMIN=$(gen 24 24)
if [ -n "$NEW_PGADMIN" ]; then
    conf_set pgadmin admin_password "$NEW_PGADMIN"
    echo "OK    pgadmin.admin_password rotated"
else
    echo "ERROR could not generate pgadmin password — left unchanged"
fi

# --- 4. cosmetic: stop sudo complaining about the per-instance hostname ----
HN=$(hostname)
if ! grep -qE "[[:space:]]${HN}([[:space:]]|\$)" /etc/hosts 2>/dev/null; then
    echo "127.0.1.1 ${HN}" >> /etc/hosts
    echo "OK    added ${HN} to /etc/hosts"
fi

# --- done -------------------------------------------------------------------
mkdir -p "$(dirname "$MARKER")"
date -u '+%Y-%m-%d %H:%M:%S UTC' > "$MARKER"
echo "panelica-firstboot complete — marker written to $MARKER"
exit 0
