#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# 1. Apache MPM: enforce prefork (required for mod_php)
# ─────────────────────────────────────────────────────────────
a2dismod mpm_event mpm_worker >/dev/null 2>&1 || true
a2enmod  mpm_prefork            >/dev/null 2>&1 || true

rm -f \
    /etc/apache2/mods-enabled/mpm_event.* \
    /etc/apache2/mods-enabled/mpm_worker.*  || true

ln -sf /etc/apache2/mods-available/mpm_prefork.load \
       /etc/apache2/mods-enabled/mpm_prefork.load   || true
ln -sf /etc/apache2/mods-available/mpm_prefork.conf \
       /etc/apache2/mods-enabled/mpm_prefork.conf   || true

# ─────────────────────────────────────────────────────────────
# 2. Moodledata volume permissions
# ─────────────────────────────────────────────────────────────
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod -R 0775              /var/www/moodledata

# ─────────────────────────────────────────────────────────────
# 3. Railway reverse-proxy: trust X-Forwarded-* headers
#    This must happen at the Apache level AND the PHP level.
# ─────────────────────────────────────────────────────────────
cat > /etc/apache2/conf-available/railway-proxy.conf <<'EOF'
# Tell Apache (and PHP via $_SERVER) that requests arriving
# over Railway's proxy are HTTPS and to trust the forwarded IP.
SetEnvIf X-Forwarded-Proto https HTTPS=on
RemoteIPHeader X-Forwarded-For
EOF

a2enmod  remoteip    >/dev/null 2>&1 || true
a2enconf railway-proxy >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────
# 4. Fix: "installation must be finished from the original IP"
#
#    Root cause: Railway's load balancer means the IP seen by
#    PHP changes between requests. Moodle stores the IP at the
#    start of install and re-checks it later in admin/index.php
#    via getremoteaddr(). The safe fix is $CFG->reverseproxy=1,
#    which makes getremoteaddr() read X-Forwarded-For instead
#    of REMOTE_ADDR — so the IP is consistent throughout.
#
#    We inject these lines into config.php immediately after
#    Moodle creates it (if they are not already present).
# ─────────────────────────────────────────────────────────────
CONFIG_PHP="/var/www/html/config.php"

inject_reverseproxy_config() {
    if [ -f "$CONFIG_PHP" ]; then
        if ! grep -q "reverseproxy" "$CONFIG_PHP"; then
            # Insert before the closing require_once line so it
            # is always loaded as part of normal CFG bootstrap.
            sed -i "/require_once.*setup\.php/i \\
\\$CFG->reverseproxy = 1;  \/\/ Trust X-Forwarded-For (Railway proxy)\\n\\$CFG->sslproxy     = 1;  \/\/ Treat proxied requests as HTTPS\\n" \
                "$CONFIG_PHP"
            echo "[entrypoint] Injected reverseproxy config into config.php"
        else
            echo "[entrypoint] reverseproxy already set in config.php — skipping"
        fi
    fi
}

# Run once now (handles redeployments where config.php already exists)
inject_reverseproxy_config

# ─────────────────────────────────────────────────────────────
# 5. Background watcher: inject as soon as Moodle creates
#    config.php during a fresh install (runs for up to 10 min)
# ─────────────────────────────────────────────────────────────
(
    WAIT=0
    MAX=600   # seconds
    INTERVAL=3
    while [ $WAIT -lt $MAX ]; do
        if [ -f "$CONFIG_PHP" ]; then
            inject_reverseproxy_config
            exit 0
        fi
        sleep $INTERVAL
        WAIT=$(( WAIT + INTERVAL ))
    done
    echo "[entrypoint] WARNING: config.php never appeared within ${MAX}s"
) &

# ─────────────────────────────────────────────────────────────
# 6. Hand off to the official Moodle entrypoint → Apache
# ─────────────────────────────────────────────────────────────
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground
