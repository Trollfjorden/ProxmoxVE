#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Trollfjorden/ProxmoxVE/feature/Riven/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus

APP="Odysseus"
var_tags="${var_tags:-ai;workspace}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/odysseus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  RELEASE=$(git ls-remote https://github.com/pewdiepie-archdaemon/odysseus.git refs/heads/dev | awk '{ print $1 }')
  current=""
  [[ -f /opt/latest.txt ]] && current=$(cat /opt/latest.txt)

  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest commit hash from repository"
    exit
  fi

  if [[ "$RELEASE" != "$current" ]]; then
    msg_ok "Update available: ${current:-not installed} → ${RELEASE}"

    msg_info "Stopping Service"
    systemctl stop odysseus
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/odysseus/data /opt/odysseus_data_backup
    cp /opt/odysseus/.env /opt/odysseus_env_backup
    msg_ok "Backed up Data"

    msg_info "Updating ${APP}"
    cd /opt/odysseus
    $STD git fetch --all
    $STD git reset --hard origin/dev
    echo "${RELEASE}" > /opt/latest.txt
    msg_ok "Updated ${APP}"

    msg_info "Updating Dependencies"
    $STD uv pip install -r requirements.txt
    if [[ -f requirements-optional.txt ]]; then
      $STD uv pip install -r requirements-optional.txt
    fi
    msg_ok "Updated Dependencies"

    msg_info "Restoring Data"
    cp -r /opt/odysseus_data_backup/. /opt/odysseus/data
    cp /opt/odysseus_env_backup /opt/odysseus/.env
    rm -rf /opt/odysseus_data_backup /opt/odysseus_env_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start odysseus
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
  fi
  exit
}

start
build_container
description

PASS=$(pct exec "$CTID" -- grep "^ODYSSEUS_ADMIN_PASSWORD=" /opt/odysseus/.env | cut -d'=' -f2)

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7000${CL}"
if [ -n "$PASS" ]; then
  echo -e "${INFO}${YW} Initial Admin Username: ${BGN}admin${CL}"
  echo -e "${INFO}${YW} Initial Admin Password: ${BGN}${PASS}${CL}"
fi
