#!/bin/sh
# Runs once before the stack starts (the `init` service). Checks the build and
# the host machine id, and prepares the directories the other services need,
# so `docker compose up -d` is the only step on any distribution.
set -eu

fail() { echo "init: $*" >&2; exit 1; }

for f in esystem-api/Speedwell.Api.dll delivery-api/Speedwell.WebDelivery.dll \
         esystem-www/index.html delivery-www/index.html; do
    [ -f "/srv/build/$f" ] || fail "build/$f missing: extract the release tarball into ./build (README, \"Install\")"
done

[ -f /srv/machine-id ] && [ -s /srv/machine-id ] \
    || fail "/etc/machine-id missing or empty on the host (run: systemd-machine-id-setup)"

# Mount points inside the read-only build mounts must exist before the app
# containers start, and a release tarball may omit the empty ones.
for d in esystem-api/config esystem-api/wwwroot \
         delivery-api/config delivery-api/wwwroot/download \
         esystem-www/config delivery-www/config; do
    mkdir -p "/srv/build/$d"
done

# db, esystem and delivery run as uid 1000.
mkdir -p /srv/data/media /srv/data/audit /srv/data/logs /srv/db_data
chown 1000:1000 /srv/data /srv/data/media /srv/data/audit /srv/data/logs /srv/db_data
chmod 700 /srv/db_data

mkdir -p /srv/certs /srv/acme
echo "init: ok"
