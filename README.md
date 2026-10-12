# Speedwell eSystem, self-hosted (Docker)

## Quick start

On an x86_64 Linux server with [Docker](https://docs.docker.com/engine/install/)
and `git` installed, using the version and build link Speedwell gave you:

    sudo install -d -o "$USER" -g "$(id -gn)" /srv/esystem   # once, as an admin
    sudo usermod -aG docker "$USER"                       # once; then log in again
    git clone https://github.com/speedwellsoftware/eSystem-docker.git /srv/esystem
    cd /srv/esystem
    cp .env.example .env
    nano .env                         # set PRIMARY_DOMAIN, DOMAINS, TZ
    bin/upgrade v4.9 'https://.../v4.9/4.9.12345.tar.gz'

The first run builds the images, which takes a few minutes.

Open `https://<PRIMARY_DOMAIN>/esystem/`. The browser warns about a
self-signed certificate until you install yours:

    bin/install-cert /path/to/site.pfx

or let Let's Encrypt issue one ([Let's Encrypt](#a-free-certificate-from-lets-encrypt)).
Everything else, step by step, is below.

## Overview

Runs one Speedwell eSystem site on a Linux server with Docker Compose:

| service    | what it is                                               |
|------------|----------------------------------------------------------|
| `db`       | PostgreSQL 18                                            |
| `esystem`  | eSystem API (.NET)                                       |
| `delivery` | Delivery API (.NET)                                      |
| `nginx`    | serves the web apps, terminates TLS                      |
| `certbot`  | optional: Let's Encrypt certificates                     |
| `init`     | one-shot check and directory preparation before startup  |

Each eSystem version has its own branch in this repository (e.g. `v4.9`).
Speedwell provides the application build for that version as a tarball
(`<version>.tar.gz`); this repository provides everything else. Fixes to a
version are published as commits on its branch.

Common tasks:

- first installation: [Install](#install)
- install a certificate from your IT department (.pfx):
  [A certificate from your IT department](#a-certificate-from-your-it-department-pfx)
- get a free certificate automatically:
  [A free certificate from Let's Encrypt](#a-free-certificate-from-lets-encrypt)
- move to a new version: [Upgrade](#upgrade)
- back up or restore the database: [Backup and restore](#backup-and-restore)
- offer different Safe Exam Browser installers:
  [Safe Exam Browser installers](#safe-exam-browser-installers)

## Requirements

- x86_64 Linux with systemd: Debian 12+, Ubuntu 22.04+, Fedora,
  RHEL / Rocky / Alma 9, openSUSE / SLES 15.
- Docker Engine 25 or newer with the Compose plugin, installed from Docker's
  own repositories: <https://docs.docker.com/engine/install/>. Podman is not
  supported.
- `git`, `zstd` and `curl`:

      sudo apt install git zstd curl        # Debian, Ubuntu
      sudo dnf install git zstd curl        # Fedora, RHEL, Rocky, Alma
      sudo zypper install git zstd curl     # openSUSE, SLES

- 4 CPU cores, 8 GB RAM, and disk for the database, uploaded media and
  backups.
- Outbound internet access while images are built (first start and
  upgrades): Docker Hub, `mcr.microsoft.com`, the Ubuntu, Debian and Alpine
  package mirrors, `github.com`, `downloads.sourceforge.net` (fonts) and the
  address of your build link. Not needed to run.
- Inbound TCP 443 (and TCP 80 for the HTTP redirect, required with Let's
  Encrypt) and UDP 443. On firewalld systems Docker opens published ports
  itself; check any network firewall in front of the server.

## Account

Run the site from one ordinary account, the *operator*, which owns
`/srv/esystem` and is in the `docker` group. Only the host setup needs an
administrator (sudo): installing packages, and once:

    sudo install -d -o "$USER" -g "$(id -gn)" /srv/esystem
    sudo usermod -aG docker "$USER"         # takes effect at the next login

Everything else in this guide runs as the operator, without sudo. Membership
of the `docker` group is as powerful as root on this server, so give it only
to the people who administer the site. Do not mix the two: running some
commands with sudo leaves root-owned files the operator cannot change.

## Install

1. **Get this repository**:

       git clone https://github.com/speedwellsoftware/eSystem-docker.git /srv/esystem
       cd /srv/esystem

   (`/srv/esystem` owned by you and you in the `docker` group, see "Account".)

2. **Settings**: copy the example and edit it. At minimum set
   `PRIMARY_DOMAIN`, `DOMAINS` and `TZ`.

       cp .env.example .env
       nano .env

3. **Fonts** (optional): the image build downloads Microsoft's Core fonts
   (Arial, Times New Roman, Verdana) by itself. For reports laid out exactly
   as on Windows, copy the Windows versions into `docker/dotnet/fonts/`
   first; see `docker/dotnet/fonts/README.md`.

4. **Install the build and start**, with the version and link Speedwell gave
   you. The first run builds the images, which takes a few minutes:

       bin/upgrade v4.9 'https://.../v4.9/4.9.12345.tar.gz'

   It switches to the version's branch, downloads and checks the build,
   unpacks it into `build/`, starts the site and shows its logs (Ctrl-C stops
   showing them; the site keeps running). Check it with:

       docker compose ps

5. **Check**: `https://<PRIMARY_DOMAIN>/esystem/` opens the eSystem and
   `https://<PRIMARY_DOMAIN>/delivery/` the delivery app. Until you install a
   certificate (next section) the browser warns about a self-signed one.

       curl -k https://localhost/esystem/api/ping

6. **Activate** the licence in the eSystem as instructed by Speedwell. The
   activation is bound to the server's `/etc/machine-id`: moving the site to
   another server, re-installing the OS, or regenerating the machine id needs
   a new activation.

To move an existing database here, restore its dump after step 4 (see
"Backup and restore").

## Certificates

nginx serves the certificate in `certs/live/<PRIMARY_DOMAIN>/`
(`fullchain.pem` and `privkey.pem`). Until one is installed it uses a
self-signed certificate, and browsers show a warning.

### A certificate from your IT department (.pfx)

1. Copy the `.pfx` (or `.p12`) file to the server, e.g. with `scp`.
2. Check `.env`: every name in `DOMAINS` must be in the certificate, and
   `PRIMARY_DOMAIN` is the first of them.
3. Install it; the script asks for the file's password:

       cd /srv/esystem
       bin/install-cert /path/to/site.pfx

   It checks that the password is right, that the key belongs to the
   certificate, that the certificate has not expired and that it covers every
   name in `DOMAINS`. Then it writes `certs/live/<PRIMARY_DOMAIN>/`
   (server certificate first, then the intermediate CA certificates) and
   reloads nginx. Nothing changes if a check fails.
4. Open `https://<PRIMARY_DOMAIN>/esystem/` from a company PC: the browser
   shows the certificate issued by your CA, without a warning.

When IT renews the certificate, run step 3 again with the new file.

A certificate delivered as PEM files instead (certificate with its chain,
and an unencrypted private key) is installed the same way:

    bin/install-cert server.pem server.key

### A free certificate from Let's Encrypt

certbot requests the certificate, renews it before it expires and reloads
nginx, with no further work. It needs the site to be reachable from the
internet:

1. Create a DNS record for every name in `DOMAINS`, pointing to this server's
   public IP address.
2. Allow TCP 80 and TCP 443 from the internet to this server. Let's Encrypt
   checks the domain over port 80, so `HTTP_PORT` must stay 80.
3. In `.env`, set the names and turn certbot on:

       PRIMARY_DOMAIN=esystem.example.org
       DOMAINS="esystem.example.org"
       COMPOSE_PROFILES=letsencrypt
       LE_EMAIL=it@example.org

   `LE_EMAIL` is the contact address of the Let's Encrypt account.
4. Start certbot and watch it (Ctrl-C stops watching):

       cd /srv/esystem
       docker compose up -d
       docker compose logs -f certbot

   Within a minute or two it logs `Successfully received certificate`, and
   the site serves it.

If certbot reports an error, the cause is almost always DNS or a firewall:
check that `http://<each name>/.well-known/acme-challenge/x` reaches this
server from outside (a 404 from nginx is the right answer). certbot retries
every hour.

certbot never replaces a certificate installed with `bin/install-cert`. To
switch from one to Let's Encrypt, remove it first:

    docker compose exec nginx sh -c 'rm -rf "/etc/letsencrypt/live/$PRIMARY_DOMAIN"'
    docker compose restart nginx

## Upgrade

You get the new version and a link to its build, e.g. version 5.0:
`https://.../v5.0/5.0.12500.tar.gz`. One command upgrades the site:

    cd /srv/esystem
    bin/upgrade v5.0 'https://.../v5.0/5.0.12500.tar.gz'

Quote the link: download links can contain `&`. A downloaded file works too:
`bin/upgrade v5.0 /tmp/5.0.12500.tar.gz`. The version in the file name
must belong to the branch: a 5.0 build goes with `v5.0`.

`bin/upgrade`:

1. fetches branch `v5.0` of this repository and switches to it, keeping your
   edits to its files,
2. runs that branch's `bin/esystem-upgrade`, so the new version installs
   itself with its own steps, which
3. downloads the build and checks it is an eSystem build of that version,
4. backs up the database into `backup/`,
5. stops the site,
6. installs the new build (the previous one is kept in `build.old/`),
7. builds the new images and starts the site,
8. shows the logs as the site starts (Ctrl-C stops showing them; the site
   keeps running).

The site keeps running through steps 1 to 4. If step 3 or 4 fails,
`bin/upgrade` switches back to the previous branch and nothing has changed.
The first requests after an upgrade can take a minute while the application
updates the database.

A fix published for the version you already run, without a new build:

    cd /srv/esystem
    git pull
    docker compose up -d --build

### Local changes

`.env`, `build/`, `data/`, `db_data/`, `certs/` and `backup/` are not in the
repository and an upgrade never touches them. Edits to files that are in it
(e.g. `config/esystem/api/appsettings.production.json`) are carried over.
If the new version changed the same file, `bin/upgrade` stops at step 1,
before anything changes, and says so. Then: save your copy of the file,
discard your edit with `git checkout -- <file>`, run `bin/upgrade`
again, and re-apply your edit to the new file.

### Rollback

An upgrade changes the database, so going back means restoring the backup
`bin/upgrade` made in step 4 (the newest file in `backup/` from before the
upgrade):

    cd /srv/esystem
    docker compose down
    git checkout v4.9
    rm -rf build && mv build.old build
    docker compose build
    bin/db-restore backup/esystem-<time of the upgrade>.sql.zst

`db-restore` starts the site when it has finished.

## Backup and restore

    bin/db-backup                                  # writes backup/esystem-<UTC time>.sql.zst
    bin/db-restore backup/esystem-20261012T030000Z.sql.zst

`db-backup` dumps the database while the site is running and deletes dumps
older than 14 days (`BACKUP_KEEP_DAYS=30 bin/db-backup` keeps 30). `db-restore` replaces the database: it
stops the site, loads the dump, and starts the site again. It accepts any
plain-format `pg_dump` of an eSystem database, zstd-compressed or not.

Nightly at 03:00, in the operator's crontab (`crontab -e`):

    0 3 * * * cd /srv/esystem && bin/db-backup >> backup/db-backup.log 2>&1

The database is only part of the site. Your server backup must also copy
`data/` (uploaded media and audit files), `.env`, `config/` and `certs/`,
and the dumps under `backup/` to another machine.

## Configuration

| path                          | purpose                                                    |
|-------------------------------|------------------------------------------------------------|
| `.env`                        | domains, ports, timezone, memory, database sizing          |
| `config/esystem/api/`         | eSystem API settings (`appsettings.production.json`)       |
| `config/delivery/api/`        | Delivery API settings (`appsettings.production.json`)      |
| `config/esystem/www/`         | optional `config.json` for the eSystem web app             |
| `config/delivery/www/`        | optional `config.json` for the delivery web app            |
| `config/nginx/allow.conf`     | optional: restrict access to listed networks               |
| `DOWNLOAD_DIR` (in `.env`)    | optional: replace the SEB installers shipped in the build (see below) |

Each `config/` directory is mounted over the matching `config` directory of
the build, so files placed there take precedence over the build's own.
Restart the app after changing its settings:
`docker compose restart esystem delivery`.

**Restrict access** to your own networks: write one `allow` line per network
to `config/nginx/allow.conf`, then apply it (everything else gets HTTP 403):

    allow 10.0.0.0/8;
    allow 192.0.2.0/24;

    docker compose exec nginx sp-nginx-conf reload

nginx only switches to a configuration that passes `nginx -t`; a broken one
is refused and the running one stays.

## Safe Exam Browser installers

Candidates download Safe Exam Browser from the delivery app
(`/delivery/api/secure/download/windows` and `/mac`). The installers Speedwell
has tested with the version ship inside the build
(`build/delivery-api/wwwroot/download/`), so normally there is nothing to do,
and each upgrade brings that version's set.

To offer other installers (e.g. a SEB release your IT has approved):

1. Put them in `seb/` in the installation directory, one per platform: a
   Windows `.exe` or `.msi`, and a macOS `.pkg` or `.dmg`. With several of
   one platform it is undefined which is served.

       cd /srv/esystem
       mkdir -p seb
       cp /path/to/SEB-installer.exe /path/to/SEB-installer.dmg seb/

2. In `.env`: `DOWNLOAD_DIR=./seb`
3. `docker compose up -d delivery`

`seb/` is kept across upgrades and keeps overriding the build's installers,
so check it against each new version's set. Remove `DOWNLOAD_DIR` from
`.env` (and run step 3 again) to go back to the build's installers.

## Operation

    docker compose ps                        # state of every service
    docker compose logs -f nginx             # follow a service's log
    docker compose restart esystem delivery
    docker compose down                      # stop the site
    docker compose up -d                     # start it

`esystem` and `delivery` start their .NET process on the first request and
stop it after 20 idle minutes, so the first request after a quiet period
takes a few seconds. `/esystem/api/ping` and `/delivery/api/ping` report
their state without waking them, for monitoring.

Application logs are written to `data/logs/` and are not deleted
automatically. Container logs are rotated by Docker.

**SELinux** (Fedora, RHEL): Docker's packages run with SELinux labelling off
by default, which this setup needs. If `docker info` lists `selinux` under
Security Options, an administrator removes `"selinux-enabled": true` from
`/etc/docker/daemon.json` and restarts Docker.

**HTTP/3** (optional): nginx listens for HTTP/3 on UDP 443 with 4 MB socket
buffers. Raise the kernel limits so they take effect:

    printf 'net.core.rmem_max=4194304\nnet.core.wmem_max=4194304\n' | sudo tee /etc/sysctl.d/90-esystem.conf
    sudo sysctl --system

## Maintaining this repository (Speedwell)

- One branch per eSystem version, named `v<major>.<minor>` (`v4.9`); fixes
  for a version are commits on its branch. `main` carries the newest version.
- Images are tagged with the exact upstream version they are built from
  (`esystem-dotnet:10.0.12`, `esystem-nginx:1.31.6`, `esystem-certbot:5.8.0`).
  Every change under `docker/` comes with a new tag in `docker-compose.yml`
  (the next upstream version, or a `-2`, `-3` suffix for our own changes), so
  existing installations build the new image on their next `up`.
- Everything the dotnet image downloads (the `.deb` packages and the Core
  fonts cabinets) is listed in `docker/dotnet/deps.txt` with its sha256 and
  addresses. A server without internet access can place those files in
  `docker/dotnet/` under the names in the first column. wkhtmltopdf is
  LGPL-3.0, source at <https://github.com/wkhtmltopdf/wkhtmltopdf>. Never
  commit font files: the Microsoft EULA forbids shipping them in a product.
