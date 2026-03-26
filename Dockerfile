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

# ── Fix: patch out the IP hijack check ────────────────────────
# Uses Python to avoid shell quoting issues with sed and $ signs.
# The three-line block only runs during initial install and is
# safe to disable permanently in reverse-proxy environments.
RUN python3 - <<'PYEOF'
path = "/var/www/html/admin/index.php"
with open(path, "r") as f:
    content = f.read()

old = (
    "    if ($adminuser->lastip !== getremoteaddr()) {\n"
    "        print_error('installhijacked', 'admin');\n"
    "    }"
)
new = (
    "    // [Railway patch] IP check disabled: container egress IP\n"
    "    // differs from browser IP behind Railway's reverse proxy.\n"
    "    // if ($adminuser->lastip !== getremoteaddr()) {\n"
    "    //     print_error('installhijacked', 'admin');\n"
    "    // }"
)

if old not in content:
    raise RuntimeError("Could not find IP check block — patch failed. Check admin/index.php manually.")

content = content.replace(old, new, 1)
with open(path, "w") as f:
    f.write(content)

print("Patch applied successfully.")
PYEOF

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