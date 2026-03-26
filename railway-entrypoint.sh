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
# On Railway the container egress IP changes between requests, so this always
# fails with "Installation must be finished from the original IP address".
#
# Approach 1: Use PHP (guaranteed available) to comment out the check block
ADMIN_INDEX="/var/www/html/admin/index.php"
if [ -f "$ADMIN_INDEX" ] && grep -q 'remoteip_check' "$ADMIN_INDEX" 2>/dev/null; then
    # The check is behind a function/variable; patch it out
    php -r '
        $path = "/var/www/html/admin/index.php";
        $code = file_get_contents($path);
        // Comment out the entire IP check block
        $code = preg_replace(
            "/if\s*\(\s*\\$remoteip_check.*?\\}/s",
            "/* [Railway patch] IP check disabled */",
            $code
        );
        file_put_contents($path, $code);
        echo "[railway-entrypoint] Patched remoteip_check in admin/index.php\n";
    '
fi

# Approach 2 (belt-and-suspenders): If config.php exists, ensure the IP
# check skip flag is present. This tells Moodle to skip the default
# IP validation even if the source patch above didn't match.
CONFIG="/var/www/html/config.php"
if [ -f "$CONFIG" ]; then
    if ! grep -q 'getremoteaddr_skip_default_ip_check' "$CONFIG" 2>/dev/null; then
        # Insert before the final require_once line (which loads lib/setup.php)
        sed -i '/require_once.*setup\.php/i \$CFG->getremoteaddr_skip_default_ip_check = true;' "$CONFIG"
        echo "[railway-entrypoint] Added IP-check skip flag to config.php"
    fi
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground