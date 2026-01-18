#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/Trollfjorden/ProxmoxVE/raw/feature/Riven/LICENSE
# Source: https://github.com/rivenmedia/riven | https://github.com/rivenmedia/riven-frontend

# Import Functions and Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_uv

# Dependencies (locales handled by LXC, curl/sudo/mc in base image)
msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  ffmpeg \
  build-essential \
  python3 \
  python3-venv \
  python3-dev \
  libffi-dev \
  libpq-dev \
  libfuse3-dev \
  pkg-config \
  fuse3
msg_ok "Installed Dependencies"

# FUSE configuration for VFS
msg_info "Configuring FUSE"
$STD sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
grep -q '^user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf
msg_ok "Configured FUSE"

# Database
PG_VERSION="18" setup_postgresql
PG_DB_NAME="riven" PG_DB_USER="riven" setup_postgresql_db

# Riven user and directories
msg_info "Creating Riven User and Directories"
useradd -r -d /opt/riven -s /usr/sbin/nologin riven 2>/dev/null || true
usermod -aG fuse riven 2>/dev/null || true
mkdir -p /mount /mnt/riven /etc/riven /dev/shm/riven-cache
chown -R riven:riven /mount /mnt/riven /dev/shm/riven-cache
chmod 755 /mount /mnt/riven
chmod 700 /dev/shm/riven-cache
msg_ok "Created Riven User and Directories"

# Backend installation
msg_info "Installing Riven Backend"
$STD git clone https://github.com/rivenmedia/riven.git /opt/riven
git -C /opt/riven rev-parse HEAD > /opt/riven_backend_version.txt
mkdir -p /opt/riven/data
cd /opt/riven
chown -R riven:riven /opt/riven
chmod 755 /opt/riven
chmod 700 /opt/riven/data
$STD sudo -u riven -H uv venv
$STD sudo -u riven -H uv sync --no-dev
msg_ok "Installed Riven Backend"

# Backend environment
RIVEN_API_KEY=$(openssl rand -hex 16)
cat <<EOF >/etc/riven/backend.env
RIVEN_API_KEY=$RIVEN_API_KEY
RIVEN_DATABASE_HOST=postgresql+psycopg2://$PG_DB_USER:$PG_DB_PASS@127.0.0.1/$PG_DB_NAME?host=/var/run/postgresql
RIVEN_DEBUG=INFO
RIVEN_FILESYSTEM_MOUNT_PATH=/mount
RIVEN_UPDATERS_LIBRARY_PATH=/mnt/riven
RIVEN_FILESYSTEM_CACHE_DIR=/dev/shm/riven-cache
EOF
chown riven:riven /etc/riven/backend.env
chmod 600 /etc/riven/backend.env

# Backend service
msg_info "Creating Backend Service"
cat <<'EOF' >/etc/systemd/system/riven-backend.service
[Unit]
Description=Riven Backend
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=riven
Group=riven
WorkingDirectory=/opt/riven
EnvironmentFile=/etc/riven/backend.env
ExecStart=/usr/local/bin/uv run python src/main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now riven-backend
msg_ok "Created Backend Service"

# Optional frontend
read -r -p "${TAB3}Install Riven Frontend? <Y/n> " prompt
if [[ ! "${prompt,,}" =~ ^(n|no)$ ]]; then
  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

  msg_info "Installing Riven Frontend"
  $STD git clone https://github.com/rivenmedia/riven-frontend.git /opt/riven-frontend
  git -C /opt/riven-frontend rev-parse HEAD > /opt/riven_frontend_version.txt
  cd /opt/riven-frontend
  $STD pnpm install
  $STD pnpm run build
  chown -R riven:riven /opt/riven-frontend
  chmod 755 /opt/riven-frontend
  msg_ok "Installed Riven Frontend"

  # Frontend environment with container IP
  import_local_ip
  AUTH_SECRET=$(openssl rand -base64 32)
  cat <<EOF >/etc/riven/frontend.env
DATABASE_URL=/opt/riven/data/riven.db
BACKEND_URL=http://127.0.0.1:8080
BACKEND_API_KEY=$RIVEN_API_KEY
AUTH_SECRET=$AUTH_SECRET
ORIGIN=http://$LOCAL_IP:3000
EOF
  chown riven:riven /etc/riven/frontend.env
  chmod 600 /etc/riven/frontend.env

  # Frontend service
  msg_info "Creating Frontend Service"
  cat <<'EOF' >/etc/systemd/system/riven-frontend.service
[Unit]
Description=Riven Frontend
After=network-online.target riven-backend.service
Wants=network-online.target

[Service]
Type=simple
User=riven
Group=riven
WorkingDirectory=/opt/riven-frontend
EnvironmentFile=/etc/riven/frontend.env
ExecStart=/usr/bin/node /opt/riven-frontend/build
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now riven-frontend
msg_ok "Created Frontend Service"
fi

motd_ssh
customize
cleanup_lxc