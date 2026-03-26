FROM moodlehq/moodle-php-apache:8.3-bookworm

# Clone Moodle v5.1.3 (fixed version)
RUN set -eux; \
    git clone --depth 1 --branch v5.1.3 https://github.com/moodle/moodle.git /var/www/html; \
    rm -rf /var/www/html/.git; \
    chown -R www-data:www-data /var/www/html

# Install and configure the runtime entrypoint
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
