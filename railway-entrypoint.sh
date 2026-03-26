#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# 1. Apache MPM: enforce prefork (required for mod_php)
# ─────────────────────────────────────────────────────────────
a2dismod mpm_event mpm_worker >/dev/null 2>&1 || true
a2enmod  mpm_prefork            >/dev/null 2>&1 || true

rm -f \
    /etc/apache2/mods-enabled/mpm_event.* \
    /etc/apache2/mods-enabled/mpm_worker.* || true

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
# ─────────────────────────────────────────────────────────────
cat > /etc/apache2/conf-available/railway-proxy.conf <<'EOF'
SetEnvIf X-Forwarded-Proto https HTTPS=on
RemoteIPHeader X-Forwarded-For
EOF

a2enmod  remoteip      >/dev/null 2>&1 || true
a2enconf railway-proxy >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────
# 4. Inject reverseproxy/sslproxy into config.php if present
#    (handles redeployments where config.php is on the volume)
# ─────────────────────────────────────────────────────────────
CONFIG_PHP="/var/www/html/config.php"
if [ -f "$CONFIG_PHP" ] && ! grep -q "reverseproxy" "$CONFIG_PHP"; then
    sed -i "/require_once.*setup\.php/i \
\$CFG->reverseproxy = 1;  \/\/ Trust X-Forwarded-For (Railway proxy)\n\
\$CFG->sslproxy     = 1;  \/\/ Treat proxied requests as HTTPS\n" \
        "$CONFIG_PHP"
    echo "[entrypoint] Injected reverseproxy + sslproxy into config.php"
fi

# ─────────────────────────────────────────────────────────────
# 5. Hand off to the official Moodle entrypoint → Apache
# ─────────────────────────────────────────────────────────────
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground