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

# Log which MPM module is loaded
apache2ctl -M 2>/dev/null | grep mpm || true

# Write a clean vhost pointing at Moodle 5.1's public/ subdirectory
cat > /etc/apache2/sites-available/000-default.conf <<'VHOST'
<VirtualHost *:80>
    DocumentRoot /var/www/moodle/public

    # Railway sits behind a reverse proxy — trust forwarded headers
    RemoteIPHeader X-Forwarded-For
    RemoteIPTrustedProxy 0.0.0.0/0

    # Rewrite REMOTE_ADDR to the forwarded IP so Moodle sees a stable client IP
    SetEnvIf X-Forwarded-For "(.+)" REMOTE_ADDR=$1
    SetEnvIf X-Forwarded-Proto https HTTPS=on

    <Directory /var/www/moodle/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
VHOST

# Enable required modules
a2enmod rewrite remoteip >/dev/null 2>&1 || true

# Post-install: patch config.php with proxy flags if Moodle is installed
# but sslproxy/reverseproxy haven't been set yet
CONFIG=/var/www/moodle/config.php
if [ -f "$CONFIG" ] && ! grep -q "sslproxy" "$CONFIG"; then
  sed -i "/require_once/i \$CFG->sslproxy = true;\n\$CFG->reverseproxy = true;" "$CONFIG"
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground