#!/usr/bin/env bash
set -euo pipefail

# Ensure only one MPM module is enabled (prefork)
a2dismod mpm_event mpm_worker >/dev/null 2>&1 || true
a2enmod mpm_prefork >/dev/null 2>&1 || true

rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.* || true
ln -sf /etc/apache2/mods-available/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.load || true
ln -sf /etc/apache2/mods-available/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf || true

# Fix permissions for the Railway Volume (moodledata)
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod -R 0775 /var/www/moodledata

# Enable mod_rewrite (needed by Moodle)
a2enmod rewrite >/dev/null 2>&1 || true

# Railway reverse-proxy: treat X-Forwarded-Proto: https as HTTPS
# Also normalize REMOTE_ADDR from X-Forwarded-For so Moodle sees
# a consistent client IP throughout the installer (fixes IP mismatch error)
cat > /etc/apache2/conf-available/railway-proxy.conf <<'EOF'
SetEnvIf X-Forwarded-Proto https HTTPS=on
SetEnvIf X-Forwarded-For "^([^,]+)" REMOTE_ADDR=$1
EOF
a2enconf railway-proxy >/dev/null 2>&1 || true

# Post-install: patch config.php with proxy flags once Moodle installer
# has created it, but only if not already patched
CONFIG=/var/www/moodle/config.php
if [ -f "$CONFIG" ] && ! grep -q "sslproxy" "$CONFIG"; then
  sed -i "/require_once/i \$CFG->sslproxy = true;\n\$CFG->reverseproxy = true;" "$CONFIG"
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground