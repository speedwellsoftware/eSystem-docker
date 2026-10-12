# `:latest` was the loosest pin in the tree. certbot has no public entrypoint
# (it reaches out to Let's Encrypt and writes certs), so this is about builds
# being reproducible rather than about exposure.
# Last bumped 2026-09-14 (certbot 5.8.0).
FROM certbot/certbot:v5.8.0

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

LABEL version="1.0"

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
