# Moodle on Railway

Quickly spin up a [Moodle](https://moodle.org) LMS sandbox on [Railway](https://railway.com) (railway.com, formerly railway.app) using Docker — ideal for development, testing, and evaluation.

> **This setup is intended for development and sandbox use only. It is not recommended for production. Use at your own risk.**

> **Moodle version:** 4.5 LTS (`MOODLE_405_STABLE` branch — latest LTS as of February 2026, tracks the latest patch release)
> **PHP version:** 8.3 (Apache, prefork MPM)
> **Base image:** [moodlehq/moodle-php-apache](https://hub.docker.com/r/moodlehq/moodle-php-apache)

---

## What this is (and isn't)

This repo gives you the fastest way to get Moodle running on Railway for:

- Local-ish development without managing a VPS
- Demoing Moodle to stakeholders
- Testing plugins, themes, or configurations
- Learning how Moodle works before committing to a production setup

**It is not hardened for production.** For a production Moodle deployment, you should consider dedicated hosting, a proper backup strategy, a tuned PHP/database configuration, and a security review.

---

## Why Railway? (railway.com / railway.app)

Railway gives you a managed cloud platform with persistent volumes, built-in PostgreSQL/MySQL databases, automatic HTTPS, and deploy-from-GitHub — everything you need to get a Moodle sandbox running without provisioning a VPS or managing Nginx configs yourself.

---

## What's in this repo

| File | Purpose |
|------|---------|
| `Dockerfile` | Pulls the official Moodle PHP/Apache image and clones the Moodle 4.5 LTS stable branch |
| `railway-entrypoint.sh` | Fixes Apache MPM config, sets up `moodledata` permissions, and configures Railway's reverse-proxy HTTPS passthrough |

---

## How the entrypoint works

Railway sits behind a reverse proxy that terminates TLS. The `railway-entrypoint.sh` script handles two Railway-specific quirks:

- **HTTPS detection** — adds an Apache rule so that `X-Forwarded-Proto: https` is correctly passed to PHP as `HTTPS=on`, preventing Moodle from generating `http://` URLs for assets.
- **MPM prefork** — ensures Apache uses the `prefork` MPM (required for `mod_php`) rather than `mpm_event`, which ships as the default in some base images.

---

## Changing the Moodle version

This repo tracks the **`MOODLE_405_STABLE`** branch — Moodle's 4.5 Long Term Support (LTS) stable branch, and the latest LTS version as of February 2026. This means every rebuild automatically picks up the latest patch release (bug fixes, security patches) without manually bumping a version tag.

To switch to a different Moodle version, change the branch in the `Dockerfile`:

```dockerfile
RUN git clone --depth 1 -b MOODLE_404_STABLE https://github.com/moodle/moodle.git /var/www/html \
```

Browse available stable branches and release tags on the [Moodle GitHub tags page](https://github.com/moodle/moodle/tags). Redeploy after changing the branch — Moodle's built-in upgrade script will run automatically on next visit if the new version is higher than the installed one.

> Always back up your database and volume before changing versions.

---

## Troubleshooting

**Mixed content / assets loading over HTTP**
Ensure `MOODLE_WWWROOT` starts with `https://` and matches your actual domain exactly.

**Permission errors on moodledata**
The entrypoint sets ownership and permissions on `/var/www/moodledata` at startup. If you see permission errors, confirm the volume is mounted at exactly `/var/www/moodledata`.

**"Database connection failed" on installer**
Double-check your database environment variables. If using Railway reference variables, make sure the variable names match the database service name shown in your Railway project.

**Build takes a long time**
The Moodle codebase is large (~400 MB). Railway caches Docker layers — subsequent deploys that don't change the `Dockerfile` will be much faster.

---

## Resources

- [Moodle documentation](https://docs.moodle.org)
- [Railway documentation](https://docs.railway.com)
- [moodlehq/moodle-php-apache on Docker Hub](https://hub.docker.com/r/moodlehq/moodle-php-apache)
- [Moodle system requirements](https://docs.moodle.org/405/en/Installing_Moodle#Requirements)

---

## Disclaimer

This project is provided as-is for sandbox and development purposes. No guarantees are made regarding security, stability, or suitability for any particular use. **Use at your own risk.** For production Moodle deployments, refer to the [official Moodle installation documentation](https://docs.moodle.org/405/en/Installing_Moodle).

---

## Licence

This repository's configuration files are released under the [MIT Licence](https://opensource.org/licenses/MIT).

Copyright (c) 2026 Jesse J.T. Zweers

Moodle itself is licenced under the [GNU GPL v3](https://docs.moodle.org/dev/License).
