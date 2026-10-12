# Build-only stage, so the pin is about reproducibility, not exposure: nothing
# from this image ships, only the static lazy-proxy binary it produces.
FROM golang:1.25.14-alpine3.24 AS builder
WORKDIR /app
COPY lazy-proxy/* .
RUN go build -ldflags="-s -w" -o lazy-proxy .

# Downloads listed in deps.txt (three .debs, the Core fonts cabinets): a file
# of that name in this directory is used as is, else it is downloaded; either
# way it must match its sha256. Fonts are the .ttf files in fonts/ when
# supplied, else the twelve in the cabinets.
FROM alpine:3.24 AS deps
RUN apk add --no-cache cabextract curl
COPY . /in/
RUN set -eu; cd /in; mkdir /out /fonts; \
    grep -v -e '^#' -e '^$' deps.txt | while read -r name sum url; do \
        if [ -f "$name" ]; then cp "$name" /out/; else curl -fsSL --retry 3 -o "/out/$name" "$url"; fi; \
        echo "$sum  /out/$name" | sha256sum -c; \
    done; \
    if ls fonts/*.[Tt][Tt][Ff] >/dev/null 2>&1; then cp fonts/*.[Tt][Tt][Ff] /fonts/; \
    else for f in /out/*.exe; do cabextract -q -L -F '*.ttf' -d /fonts "$f"; done; fi; \
    rm /out/*.exe

# Pinned to an exact .NET patch on Ubuntu noble. A release branch keeps its
# pins; security fixes reach it as a commit that bumps them together with the
# esystem-dotnet tag in docker-compose.yml. Stay on noble: libssl1.1 below
# comes from the Ubuntu focal pool and has no newer-release equivalent, so a
# distro move needs wkhtmltopdf's dependencies fixed first.
FROM mcr.microsoft.com/dotnet/aspnet:10.0.12-noble

WORKDIR /app

# wkhtmltopdf 0.12.6 (built 2022) links libssl1.1 and libjpeg.so.62, which
# Ubuntu noble does not ship; all three come from the deps stage.
COPY --from=deps /out/ /tmp/
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        /tmp/libssl1.1.deb \
        /tmp/libjpeg62.deb \
        /tmp/wkhtmltox.deb \
        krb5-user \
        locales && \
    sed -i '/en_GB.UTF-8/s/^# //' /etc/locale.gen && locale-gen && \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb

# en-GB default culture. On Linux with no locale set, .NET falls back to
# InvariantCulture (US-style MM/dd dates); the app formats report/exam dates
# with the process culture, so they must render en-GB (dd/MM) — matching the
# Windows hosts the report baselines were captured on. ICU is in the base
# image so LANG drives the .NET culture; locale-gen (above) backs it for any
# glibc-dependent tooling (wkhtmltopdf). Prior to this the containers had no
# LANG, so both esystem and delivery rendered US dates on the docker fleet.
ENV LANG=en_GB.UTF-8 \
    LC_ALL=en_GB.UTF-8 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false

# Arial, Times New Roman and Verdana (see fonts/README.md). Server-side
# rendering (wkhtmltopdf reports, SkiaSharp chart-label measurement)
# otherwise falls back Verdana -> DejaVu Sans and every
# text-metric-sensitive layout diverges from the Windows version.
COPY --from=deps /fonts /usr/local/share/fonts/windows
COPY --from=builder /app/lazy-proxy /usr/local/bin/lazy-proxy
