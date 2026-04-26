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
  redis-server \
  build-essential \
  python3-dev \
  python3-venv \
  libffi-dev \
  pkg-config \
  libpq-dev \
  fuse3 \
  libfuse3-dev
msg_ok "Installed Dependencies"

msg_info "Configuring FUSE"
$STD sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
grep -q '^user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf
msg_ok "Configured FUSE"

NODE_VERSION="24" setup_nodejs
PG_VERSION="18" setup_postgresql
PG_DB_NAME="rivents" PG_DB_USER="rivents" setup_postgresql_db

msg_info "Installing pnpm"
PNPM_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/rivenmedia/riven-ts/refs/heads/main/package.json" | jq -r '.packageManager | split("@")[1]' | cut -d'+' -f1)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable pnpm
$STD corepack prepare pnpm@${PNPM_VERSION} --activate
msg_ok "Installed pnpm"

msg_info "Setting up directories"
mkdir -p /mount/riven /mnt/riven /dev/shm/rivents-cache
mkdir -p /opt/rivents
chmod 755 /mount/riven /mnt/riven
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
$STD pnpm turbo generate-schemas
$STD pnpm turbo telemetry disable
$STD pnpm turbo run build --no-daemon --filter=@repo/riven
shopt -s dotglob
cp -a /opt/rivents.build/* /opt/rivents/
shopt -u dotglob
rm -rf /opt/rivents.build
cd /opt/rivents
$STD pnpm install --prod --frozen-lockfile --ignore-scripts
msg_ok "Built RivenTS"

msg_info "Configuring RivenTS"
export TZ=$(cat /etc/timezone)

cat <<EOF >>/opt/rivents/apps/riven/.env.riven
TZ=${TZ}
# ProxmoxVE Deployment Configs
RIVEN_SETTING__databaseUrl="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"
RIVEN_SETTING__redisUrl="redis://127.0.0.1:6379"
RIVEN_SETTING__vfsMountPath="/mnt/riven"
RIVEN_SETTING__logLevel="info"
RIVEN_SETTING__logDirectory="/opt/rivents/logs"
# Optional Features (Uncomment to enable)
# RIVEN_SETTING__vfsDebugLogging=true
# RIVEN_SETTING__unsafeClearQueuesOnStartup=false
# RIVEN_SETTING__unsafeRefreshDatabaseOnStartup=false
EOF

cat <<EOF >>/opt/rivents/packages/plugin-seerr/.env.seerr
TZ=${TZ}
# LOG_LEVEL="info"
# External Seerr Connection
# RIVEN_PLUGIN_SETTING__plugin-seerr__url="http://<seerr-lxc-ip>:5055"
# RIVEN_PLUGIN_SETTING__plugin-seerr__apiKey="your_seerr_api_key"
EOF

cat <<EOF >>/opt/rivents/packages/plugin-plex/.env.plex
TZ=${TZ}
# PLEX_CLAIM=""
# External Plex Connection
# RIVEN_PLUGIN_SETTING__plugin-plex__plexServerUrl="http://<plex-lxc-ip>:32400"
# RIVEN_PLUGIN_SETTING__plugin-plex__plexToken="your_plex_token"
# RIVEN_PLUGIN_SETTING__plugin-plex__plexLibraryPath="/mnt/riven"
EOF

chmod 600 /opt/rivents/apps/riven/.env.riven
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
WorkingDirectory=/opt/rivents/apps/riven
EnvironmentFile=/opt/rivents/apps/riven/.env.riven
ExecStart=/usr/bin/node --conditions production --enable-source-maps /opt/rivents/apps/riven/dist/program/index.js
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
