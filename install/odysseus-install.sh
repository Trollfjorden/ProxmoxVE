#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential git
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.13" setup_uv

msg_info "Cloning ${APP} dev branch"
$STD git clone -b dev https://github.com/pewdiepie-archdaemon/odysseus.git /opt/odysseus
git -C /opt/odysseus rev-parse HEAD > /opt/latest.txt
msg_ok "Cloned ${APP} dev branch"

msg_info "Setting up ${APP}"
cd /opt/odysseus
$STD uv venv
ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)

cp .env.example .env
if grep -q "^APP_BIND=" .env; then
  sed -i 's/^APP_BIND=.*/APP_BIND=0.0.0.0/' .env
else
  echo "APP_BIND=0.0.0.0" >> .env
fi

if grep -q "^APP_PORT=" .env; then
  sed -i 's/^APP_PORT=.*/APP_PORT=7000/' .env
else
  echo "APP_PORT=7000" >> .env
fi

echo "ODYSSEUS_ADMIN_PASSWORD=$ADMIN_PASSWORD" >> .env

$STD uv pip install -r requirements.txt
$STD /opt/odysseus/.venv/bin/python setup.py
msg_ok "Set up ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/odysseus.service
[Unit]
Description=Odysseus Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/odysseus
ExecStart=/opt/odysseus/.venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 7000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now odysseus
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
