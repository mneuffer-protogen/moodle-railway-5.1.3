#!/usr/bin/env bash
set -eo pipefail

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

# Enable mod_rewrite
a2enmod rewrite >/dev/null 2>&1 || true

# Railway reverse-proxy: treat X-Forwarded-Proto: https as HTTPS
cat > /etc/apache2/conf-available/railway-proxy.conf <<'EOF'
SetEnvIf X-Forwarded-Proto https HTTPS=on
EOF
a2enconf railway-proxy >/dev/null 2>&1 || true

# CLI install on first boot only
CONFIG=/var/www/moodle/config.php

if [ ! -f "$CONFIG" ]; then
  echo ">>> No config.php found — running Moodle CLI installer..."

  : "${MOODLE_URL:?ERROR: MOODLE_URL is not set}"
  : "${PGHOST:?ERROR: PGHOST is not set}"
  : "${PGDATABASE:?ERROR: PGDATABASE is not set}"
  : "${PGUSER:?ERROR: PGUSER is not set}"
  : "${PGPASSWORD:?ERROR: PGPASSWORD is not set}"
  : "${MOODLE_ADMIN_PASS:?ERROR: MOODLE_ADMIN_PASS is not set}"

  echo ">>> DB: $PGHOST:$PGPORT/$PGDATABASE as $PGUSER"
  echo ">>> URL: $MOODLE_URL"

  sudo -u www-data php /var/www/moodle/admin/cli/install.php \
    --lang=en \
    --wwwroot="${MOODLE_URL}" \
    --dataroot=/var/www/moodledata \
    --dbtype=pgsql \
    --dbhost="${PGHOST}" \
    --dbname="${PGDATABASE}" \
    --dbuser="${PGUSER}" \
    --dbpass="${PGPASSWORD}" \
    --dbport="${PGPORT:-5432}" \
    --fullname="Moodle" \
    --shortname="moodle" \
    --adminuser=admin \
    --adminpass="${MOODLE_ADMIN_PASS}" \
    --adminemail="admin@example.com" \
    --non-interactive \
    --agree-license

  echo ">>> CLI install complete."

  sed -i "/require_once/i \$CFG->sslproxy = true;\n\$CFG->reverseproxy = true;" "$CONFIG"
  chown www-data:www-data "$CONFIG"

  echo ">>> config.php patched with sslproxy + reverseproxy."
fi

# Start the original entrypoint + Apache
exec /usr/local/bin/moodle-docker-php-entrypoint apache2-foreground