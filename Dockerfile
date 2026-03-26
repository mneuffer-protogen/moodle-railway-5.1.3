FROM moodlehq/moodle-php-apache:8.3-bookworm

# ── Security: recommended PHP hardening ──────────────────────
RUN echo "zend.exception_ignore_args = On" \
    > /usr/local/etc/php/conf.d/moodle-security.ini

# ── Moodle source ─────────────────────────────────────────────
RUN set -eux; \
    git clone --depth 1 --branch v5.1.3 \
        https://github.com/moodle/moodle.git /var/www/html; \
    rm -rf /var/www/html/.git; \
    chown -R www-data:www-data /var/www/html

# ── Fix: patch out the IP hijack check in admin/index.php ─────
# Moodle compares the IP stored at DB-write time with the IP at
# admin/index.php. On Railway the container egress IP changes
# between requests so this check always fails. The block is
# install-only and safe to disable permanently.
# We use a line-by-line search so whitespace/indent never matters.
RUN sed -i '/lastip.*getremoteaddr\|getremoteaddr.*lastip/{s|^|// [Railway patch] |;n;s|^|// [Railway patch] |;n;s|^|// [Railway patch] |}' \
    /var/www/html/admin/index.php \
 && echo "Railway patch applied: IP-check lines commented out"

# ── Composer dependencies ─────────────────────────────────────
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN set -eux; \
    cd /var/www/html; \
    composer install --no-dev --classmap-authoritative --no-interaction; \
    chown -R www-data:www-data /var/www/html/vendor

# ── Runtime entrypoint ────────────────────────────────────────
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]