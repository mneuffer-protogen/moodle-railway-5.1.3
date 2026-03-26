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
if [ -f "$ADMIN_INDEX" ]; then
    php -r '
        $path = "/var/www/html/admin/index.php";
        $code = file_get_contents($path);
        
        // The exact literal string in Moodle 4.x/5.x
        $search = "if (\$adminuser->lastip !== getremoteaddr()) {";
        $replace = "if (false) { // [Railway patch] bypassed: if (\$adminuser->lastip !== getremoteaddr()) {";
        
        if (strpos($code, $search) !== false) {
            $code = str_replace($search, $replace, $code);
            file_put_contents($path, $code);
            echo "[railway-entrypoint] Patched adminuser->lastip check in admin/index.php\n";
        }
    '
fi

# Approach 2: Proper Proxy Configuration
# Moodle needs to know it is behind a reverse proxy that terminates SSL
CONFIG="/var/www/html/config.php"
if [ -f "$CONFIG" ]; then
    if ! grep -q 'reverseproxy' "$CONFIG" 2>/dev/null; then
        # Insert before the final require_once line (which loads lib/setup.php)
        sed -i "/require_once.*setup\.php/i \\\$CFG->reverseproxy = true;\n\$CFG->sslproxy = true;" "$CONFIG"
        echo "[railway-entrypoint] Added reverse proxy settings to config.php"
    fi
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground