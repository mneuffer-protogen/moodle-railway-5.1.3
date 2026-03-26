FROM moodlehq/moodle-php-apache:8.3-bookworm

# Clone Moodle 5.1.3 by tag and remove .git to reduce image size
RUN git clone --depth 1 -b v5.1.3 https://github.com/moodle/moodle.git /var/www/moodle \
 && rm -rf /var/www/moodle/.git \
 && chown -R www-data:www-data /var/www/moodle

# Point Apache DocumentRoot at the public/ subdirectory (required from Moodle 5.1+)
RUN sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/moodle/public|g' \
        /etc/apache2/sites-available/000-default.conf \
 && sed -i 's|<Directory /var/www/html>|<Directory /var/www/moodle/public>|g' \
        /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf 2>/dev/null || true

# Install and configure the runtime entrypoint
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]