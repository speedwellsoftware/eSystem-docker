# Pinned to an exact nginx patch and Alpine release. A release branch keeps
# its pins; security fixes reach it as a commit that bumps them together with
# the esystem-nginx tag in docker-compose.yml. HTTP/3 makes this load-bearing:
# the 2026 nginx CVEs (CVE-2026-40460, CVE-2026-42530, CVE-2026-90439) were all
# in the QUIC stack and fixed in-series, so never pin below 1.31.6.
#
# Check the config still loads after a bump:
#   docker build -t esystem-nginx:test . && \
#     docker run --rm -e PRIMARY_DOMAIN=example.test -e DOMAINS=example.test \
#       esystem-nginx:test nginx -t
FROM nginx:1.31.6-alpine3.24

RUN apk add --no-cache openssl gettext \
 && addgroup -g 1000 sp \
 && adduser -D -u 1000 -G sp sp

# conf/ is the fallback copy of the config. The live one is conf/ mounted
# from the checkout at /etc/nginx/sp-src; sp-nginx-conf renders either into
# /etc/nginx/gen and links /etc/nginx/nginx.conf to the last that passed
# nginx -t.
COPY ./conf/                  /etc/nginx/sp-baked/
COPY ./sp-nginx-conf          /usr/local/bin/sp-nginx-conf
COPY ./entrypoint.sh          /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/sp-nginx-conf \
 && mkdir -p /var/cache/nginx /run/nginx /var/www/certbot /etc/letsencrypt \
 && chown -R sp:sp /var/cache/nginx /run/nginx /var/www/certbot

# Run as root so the entrypoint can write the bootstrap self-signed cert
# into /etc/letsencrypt on first boot; nginx itself drops to `sp` workers
# (set `user sp sp;` in conf/nginx.conf.template if you want to be explicit).
LABEL version="1.0"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
