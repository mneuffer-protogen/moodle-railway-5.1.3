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

    <Directory /var/www/moodle/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
VHOST

# Railway reverse-proxy: treat X-Forwarded-Proto: https as HTTPS
cat > /etc/apache2/conf-available/railway-proxy.conf <<'EOF'
SetEnvIf X-Forwarded-Proto https HTTPS=on
EOF
a2enconf railway-proxy >/dev/null 2>&1 || true

# Enable mod_rewrite (needed by Moodle)
a2enmod rewrite >/dev/null 2>&1 || true

# Write a Moodle config stub before the installer runs.
# Only write if config.php doesn't already exist (i.e. first boot).
CONFIG=/var/www/moodle/config.php
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<'MOODLECFG'
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();
$CFG->wwwroot   = getenv('MOODLE_URL') ?: 'http://localhost';
$CFG->dataroot  = '/var/www/moodledata';
$CFG->directorypermissions = 0777;
$CFG->sslproxy      = true;
$CFG->reverseproxy  = true;
require_once(__DIR__ . '/lib/setup.php');
MOODLECFG
  chown www-data:www-data "$CONFIG"
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground