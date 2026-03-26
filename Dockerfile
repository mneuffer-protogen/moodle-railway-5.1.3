FROM moodlehq/moodle-php-apache:8.3-bookworm

# Clone Moodle 5.1.3 by tag and remove .git to reduce image size
RUN git clone --depth 1 -b v5.1.3 https://github.com/moodle/moodle.git /var/www/moodle \
 && rm -rf /var/www/moodle/.git \
 && chown -R www-data:www-data /var/www/moodle

ENV APACHE_DOCUMENT_ROOT=/var/www/moodle/public

# Install and configure the runtime entrypoint
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]