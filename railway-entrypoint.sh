#!/usr/bin/env bash
set -euo pipefail

# Ensure only one MPM module is enabled (prefork)
a2dismod mpm_event mpm_worker >/dev/null 2>&1 || true
a2enmod mpm_prefork >/dev/null 2>&1 || true

# Remove any leftover symlinks that could cause conflicts
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.* || true
ln -sf /etc/apache2/mods-available/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.load || true
ln -sf /etc/apache2/mods-available/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf || true

# Fix permissions for the Railway Volume (moodledata)
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod -R 0775 /var/www/moodledata

# Log which MPM module is loaded
apache2ctl -M 2>/dev/null | grep mpm || true

# Railway reverse-proxy: treat request as HTTPS when the proxy indicates it
echo "SetEnvIf X-Forwarded-Proto https HTTPS=on" > /etc/apache2/conf-available/railway-proxy.conf
a2enconf railway-proxy >/dev/null 2>&1 || true

# ── Railway fix: patch out the IP-hijack check in admin/index.php ──
# Moodle compares the IP stored at install time with the current request IP.
# On Railway the container egress IP changes between requests, so this check
# always fails with "Installation must be finished from the original IP address".
# We comment out the 3-line block (if-check, print_error, closing brace).
ADMIN_INDEX="/var/www/html/admin/index.php"
if [ -f "$ADMIN_INDEX" ] && grep -q 'lastip.*getremoteaddr\|getremoteaddr.*lastip' "$ADMIN_INDEX"; then
    sed -i '/lastip.*getremoteaddr\|getremoteaddr.*lastip/{
        s|^|// [Railway patch] |
        n; s|^|// [Railway patch] |
        n; s|^|// [Railway patch] |
    }' "$ADMIN_INDEX"
    echo "[railway-entrypoint] Patched IP-check in admin/index.php"
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground