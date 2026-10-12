#!/bin/sh
set -eu

: "${PRIMARY_DOMAIN:?PRIMARY_DOMAIN required}"
: "${DOMAINS:?DOMAINS required}"
: "${LE_EMAIL:?LE_EMAIL required}"

LIVE_DIR="/etc/letsencrypt/live/${PRIMARY_DOMAIN}"
WEBROOT=/var/www/certbot
# Last outcome: "<epoch> <ok|fail> <message>".
STATUS=/etc/letsencrypt/renew-status
INTERVAL=43200
RETRY=3600

log() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [certbot] $*"
}

STAGING_FLAG=""
if [ "${LE_STAGING:-0}" = "1" ]; then
    STAGING_FLAG="--staging"
    log "LE_STAGING=1: using Let's Encrypt staging endpoint"
fi

# Build the -d flag list from $DOMAINS (space-separated).
DOMAIN_ARGS=""
for d in $DOMAINS; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $d"
done

reload_nginx() {
    # Requires `pid: "service:nginx"` in compose so we see nginx's PIDs.
    pid=$(pgrep -f 'nginx: master process' | head -n 1)
    if [ -n "$pid" ]; then
        log "HUPping nginx (pid $pid)"
        kill -HUP "$pid" || true
    else
        log "nginx master not found, skipping reload"
    fi
}

cert_is_real() {
    # The bootstrap self-signed has issuer CN=$PRIMARY_DOMAIN. A real LE
    # cert is issued by "(STAGING) Let's Encrypt" or "Let's Encrypt".
    [ -s "$LIVE_DIR/fullchain.pem" ] || return 1
    openssl x509 -in "$LIVE_DIR/fullchain.pem" -noout -issuer 2>/dev/null \
        | grep -qi "let's encrypt"
}

cert_is_installed() {
    # A certificate placed by the operator (an enterprise CA, a purchased
    # certificate): present, not Let's Encrypt, and not nginx's bootstrap,
    # which nginx marks with .bootstrap. certbot must never replace it.
    [ -s "$LIVE_DIR/fullchain.pem" ] && [ ! -L "$LIVE_DIR/fullchain.pem" ] \
        && [ ! -e "$LIVE_DIR/.bootstrap" ] && ! cert_is_real
}

cert_matches_domains() {
    # The live cert's SAN list equals $DOMAINS (order-insensitive). `certbot
    # renew` only ever re-requests the names already in the lineage, so a
    # DOMAINS change has to go through certonly to reach the certificate.
    want=$(printf '%s\n' $DOMAINS | sort -u)
    have=$(openssl x509 -in "$LIVE_DIR/fullchain.pem" -noout -ext subjectAltName 2>/dev/null \
        | tr ',' '\n' | sed -n 's/^ *DNS://p' | sort -u)
    [ "$want" = "$have" ]
}

# Run certbot, timestamping every line of its output; returns its exit code.
# The last error line is left in $CERTBOT_ERROR for the status file.
CERTBOT_ERROR=""
run_certbot() {
    out=$(mktemp)
    rc=0
    certbot "$@" >"$out" 2>&1 || rc=$?
    while IFS= read -r line; do
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $line"
    done <"$out"
    CERTBOT_ERROR=$(grep -o 'with error: .*' "$out" | head -n 1 | cut -c13- | cut -c1-160)
    rm -f "$out"
    return "$rc"
}

write_status() {
    printf '%s %s %s\n' "$(date -u +%s)" "$1" "$2" >"$STATUS.tmp"
    mv -f "$STATUS.tmp" "$STATUS"
}

# Wait for nginx to be answering on :80 inside the compose network so the
# webroot challenge can be served.
log "waiting for nginx :80"
i=0
while ! nc -z nginx 80 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
        log "nginx did not come up in 60s, continuing anyway"
        break
    fi
    sleep 1
done

# One loop for issuance, SAN changes and renewal, so a failed first issuance
# is retried instead of restarting the container, and a (re)started container
# checks its certificate immediately rather than after the first interval.
# A cert whose SAN list no longer matches DOMAINS (a name added to .env, then
# `docker compose up -d`) is reissued through the same certonly call: with
# --cert-name it updates the existing lineage in place, and
# --renew-with-new-domains makes that unconditional rather than a prompt.
while :; do
    if cert_is_installed; then
        write_status fail "certificate in $LIVE_DIR was installed by hand, not issued by certbot; leaving it alone"
        log "certificate in $LIVE_DIR was not issued by certbot; leaving it alone (remove COMPOSE_PROFILES=letsencrypt to stop this service)"
        sleep "$INTERVAL"
        continue
    fi
    if cert_is_real && cert_matches_domains; then
        log "renew check for $PRIMARY_DOMAIN"
        if run_certbot renew --webroot -w "$WEBROOT" --non-interactive --quiet; then
            write_status ok "renew check passed"
            reload_nginx
        else
            write_status fail "renew failed: ${CERTBOT_ERROR:-certbot renew exited non-zero}"
            log "renew failed, retrying in ${RETRY}s"
            sleep "$RETRY"
            continue
        fi
    else
        if cert_is_real; then
            log "certificate SANs differ from DOMAINS, reissuing for: $DOMAINS"
            done_msg="certificate reissued for new domains"
        else
            log "no real cert yet, running certonly for: $DOMAINS"
            done_msg="certificate issued"
            # Remove the bootstrap dir so certbot doesn't refuse to overwrite.
            rm -rf "$LIVE_DIR" "/etc/letsencrypt/archive/${PRIMARY_DOMAIN}" \
                   "/etc/letsencrypt/renewal/${PRIMARY_DOMAIN}.conf" 2>/dev/null || true
        fi
        # shellcheck disable=SC2086  # STAGING_FLAG and DOMAIN_ARGS are word lists
        if run_certbot certonly \
                --webroot -w "$WEBROOT" \
                --non-interactive --agree-tos \
                --email "$LE_EMAIL" \
                --cert-name "$PRIMARY_DOMAIN" \
                --renew-with-new-domains \
                $STAGING_FLAG \
                $DOMAIN_ARGS; then
            write_status ok "$done_msg"
            reload_nginx
        else
            write_status fail "issuance failed: ${CERTBOT_ERROR:-certbot certonly exited non-zero}"
            log "issuance failed, retrying in ${RETRY}s"
            sleep "$RETRY"
            continue
        fi
    fi
    sleep "$INTERVAL"
done
