#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rivenmedia/riven-ts

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  build-essential \
  pkg-config \
  redis-server \
  python3 \
  fuse3 \
  libfuse-dev
msg_ok "Installed Dependencies"

msg_info "Configuring FUSE"
$STD sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
grep -q '^user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf
msg_ok "Configured FUSE"

NODE_VERSION="26" setup_nodejs
PG_VERSION="18" setup_postgresql
PG_DB_NAME="rivents" PG_DB_USER="rivents" setup_postgresql_db

msg_info "Installing pnpm"
PNPM_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/rivenmedia/riven-ts/refs/heads/main/package.json" | jq -r '.packageManager | split("@")[1]' | cut -d'+' -f1)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable pnpm
$STD corepack prepare pnpm@${PNPM_VERSION} --activate
msg_ok "Installed pnpm"

msg_info "Setting up directories"
mkdir -p /mnt/rivents /dev/shm/rivents-cache
mkdir -p /opt/rivents
chmod 755 /mnt/rivents
chmod 700 /dev/shm/rivents-cache
msg_ok "Set up directories"

msg_info "Downloading RivenTS"
$STD git clone https://github.com/rivenmedia/riven-ts.git /opt/rivents.build
git -C /opt/rivents.build rev-parse HEAD > /opt/latest.txt
msg_ok "Downloaded RivenTS"

msg_info "Building RivenTS"
export NODE_OPTIONS="--max-old-space-size=4096"
cd /opt/rivents.build
$STD pnpm install --frozen-lockfile --force
$STD pnpm turbo telemetry disable
$STD pnpm turbo run build --no-daemon --filter=@repo/riven
$STD pnpm --filter @repo/riven --prod deploy /opt/rivents
cd /opt/rivents
rm -rf /opt/rivents.build
msg_ok "Built RivenTS"

msg_info "Configuring RivenTS"
export TZ=$(cat /etc/timezone)

cat <<EOF >>/opt/rivents/.env.riven
TZ=${TZ}
# Core Settings
RIVEN_SETTING__databaseUrl="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"
RIVEN_SETTING__redisUrl="redis://127.0.0.1:6379"
RIVEN_SETTING__vfsMountPath="/mnt/rivents"
RIVEN_SETTING__logLevel="debug"
RIVEN_SETTING__logDirectory="/opt/rivents/logs"

# Content settings
# RIVEN_SETTING__preferSeasonPacks=true
# RIVEN_SETTING__attemptUnknownDownloads=false
# RIVEN_SETTING__dubbedAnimeOnly=false
# RIVEN_SETTING__maximumScrapeAttempts=1234
# RIVEN_SETTING__minimumAverageBitrateMovies=1234
# RIVEN_SETTING__minimumAverageBitrateEpisodes=1234
# RIVEN_SETTING__scheduleOffsetMinutes=30
# RIVEN_SETTING__scrapeCooldownHours=[2,6,24]
# RIVEN_SETTING__unknownAirDateOffsetDays=7
# RIVEN_SETTING__enabledPlugins=['comet' | 'listrr' | 'mdblist' | 'notifications' | 'plex' | 'seerr' | 'stremthru' | 'subdl' | 'tmdb' | 'torrentio' | 'tvdb']

# Development & Troubleshooting Settings (uncomment to enable)
# SENTRY_SPOTLIGHT=1
# SENTRY_SPOTLIGHT_CLEAR_ON_STARTUP=1
# RIVEN_SETTING__loggingEnabled=true
# RIVEN_SETTING__logShowStackTraces=true
# RIVEN_SETTING__vfsDebugLogging=true
# RIVEN_SETTING__databaseDebugLogging=true
# RIVEN_SETTING__enabledLogTransports=["console","file"]
# RIVEN_SETTING__unsafeClearQueuesOnStartup=true
# RIVEN_SETTING__unsafeRefreshDatabaseOnStartup=true
# RIVEN_SETTING__unsafeWipeRedisOnStartup=true
# RIVEN_SETTING__unsafeWipeDatabaseOnStartup=true

# Plugins:
# Comet
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_COMET__url="<url>"

# Stremthru
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_STREMTHRU__stremThruUrl="<url>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_STREMTHRU__realdebridApiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_STREMTHRU__alldebridApiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_STREMTHRU__premiumizeApiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_STREMTHRU__torboxApiKey="<key>"

# Torrentio
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_TORRENTIO__filter="sort=qualitysize%7Cqualityfilter=threed,480p,scr,cam"

# Seerr
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SEERR__url="http://<seerr-lxc-ip>:5055"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SEERR__apiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SEERR__filter="approved"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SEERR__updateIntervalSeconds=60

# Plex
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_PLEX__plexServerUrl="http://<plex-lxc-ip>:32400"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_PLEX__plexToken="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_PLEX__plexLibraryPath="/mnt/riven"

# SubDL
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SUBDL__apiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_SUBDL__languages="[en]"

# TMDB
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_TMDB__apiKey="<key>"

# TVDB
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_TVDB__apiKey="<key>"

# Listrr
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_LISTRR__apiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_LISTRR__movieLists=[1234]
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_LISTRR__showLists=[1234]
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_LISTRR__updateIntervalSeconds=86400

# MDBList
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_MDBLIST__apiKey="<key>"
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_MDBLIST__lists=[1234]
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_MDBLIST__updateIntervalSeconds=86400

# Trakt
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_TRAKT__apiKey="<key>"

# Notifications
# RIVEN_PLUGIN_SETTING__REPO_PLUGIN_NOTIFICATIONS__urls=[discord://id/token, json://host/path]
EOF

chmod 600 /opt/rivents/.env.riven
msg_ok "Configured RivenTS"

msg_info "Creating Service"
cat <<EOF >/lib/systemd/system/rivents.service
[Unit]
Description=RivenTS Service
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rivents
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node --conditions production --env-file-if-exists=.env.riven --enable-source-maps dist/program/lib/index.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now postgresql redis-server rivents
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
