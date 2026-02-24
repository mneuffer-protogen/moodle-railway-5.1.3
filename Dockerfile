FROM moodlehq/moodle-php-apache:8.3-bookworm

# Clone the Moodle 4.5 LTS stable branch (tracks latest patch releases) and remove the .git directory to reduce image size
RUN git clone --depth 1 -b MOODLE_405_STABLE https://github.com/moodle/moodle.git /var/www/html \
 && rm -rf /var/www/html/.git \
 && chown -R www-data:www-data /var/www/html

# Install and configure the runtime entrypoint
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
