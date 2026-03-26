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
RUN python3 << 'PYEOF'
import re, sys

path = "/var/www/html/admin/index.php"
with open(path) as f:
    lines = f.readlines()

# Find the line containing the lastip check (strip to ignore whitespace)
idx = None
for i, line in enumerate(lines):
    if "lastip" in line and "getremoteaddr" in line and "if" in line:
        idx = i
        break

if idx is None:
    print("ERROR: could not find lastip check line", file=sys.stderr)
    sys.exit(1)

# Comment out that line and the next two (print_error + closing brace)
for i in range(idx, min(idx + 3, len(lines))):
    lines[i] = "    // [Railway patch] " + lines[i].lstrip()

with open(path, "w") as f:
    f.writelines(lines)

print(f"Patch applied: commented lines {idx+1}–{idx+3} in {path}")
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