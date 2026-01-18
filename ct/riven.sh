#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Trollfjorden/ProxmoxVE/feature/Riven/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/Trollfjorden/ProxmoxVE/raw/feature/Riven/LICENSE
# Source: https://github.com/rivenmedia/riven | https://github.com/rivenmedia/riven-frontend

APP="Riven"
var_tags="${var_tags:-arr;media;debrid}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_fuse="${var_fuse:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/riven ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  RELEASE_BACKEND=$(git ls-remote https://github.com/rivenmedia/riven.git HEAD | awk '{ print $1 }')
  if [[ -d /opt/riven-frontend ]]; then
    RELEASE_FRONTEND=$(git ls-remote https://github.com/rivenmedia/riven-frontend.git HEAD | awk '{ print $1 }')
  fi

  UPD_BACKEND=false
  if [[ ! -f /opt/riven_backend_version.txt ]] || [[ "${RELEASE_BACKEND}" != "$(cat /opt/riven_backend_version.txt)" ]]; then
    UPD_BACKEND=true
  fi

  UPD_FRONTEND=false
  if [[ -d /opt/riven-frontend ]]; then
    if [[ ! -f /opt/riven_frontend_version.txt ]] || [[ "${RELEASE_FRONTEND}" != "$(cat /opt/riven_frontend_version.txt)" ]]; then
      UPD_FRONTEND=true
    fi
  fi

  if [[ "$UPD_BACKEND" == "false" && "$UPD_FRONTEND" == "false" ]]; then
    msg_ok "No update required. ${APP} is already at the latest version."
    exit
  fi

  source <(curl -fsSL https://raw.githubusercontent.com/Trollfjorden/ProxmoxVE/feature/Riven/misc/install.func)

  msg_info "Stopping Services"
  systemctl stop riven-backend 2>/dev/null || true
  [[ -d /opt/riven-frontend ]] && systemctl stop riven-frontend 2>/dev/null || true
  msg_ok "Stopped Services"

  update_os
  setup_uv
  PG_VERSION="18" setup_postgresql

  if [[ "$UPD_BACKEND" == "true" ]]; then
    msg_info "Updating ${APP} Backend"
    cd /opt/riven
    $STD git fetch --all
    $STD git reset --hard origin/main
    echo "${RELEASE_BACKEND}" >/opt/riven_backend_version.txt
    $STD sudo -u riven -H uv sync --no-dev
    msg_ok "Updated ${APP} Backend"
  fi

  if [[ -d /opt/riven-frontend ]]; then
    if [[ "$UPD_FRONTEND" == "true" ]]; then
      NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
      msg_info "Updating ${APP} Frontend"
      cd /opt/riven-frontend
      $STD git fetch --all
      $STD git reset --hard origin/main
      echo "${RELEASE_FRONTEND}" >/opt/riven_frontend_version.txt
      $STD pnpm install
      $STD pnpm run build
      msg_ok "Updated ${APP} Frontend"
    fi
  fi

  msg_info "Starting Services"
  systemctl start riven-backend
  [[ -d /opt/riven-frontend ]] && systemctl start riven-frontend
  msg_ok "Started Services"

  msg_ok "Riven LXC updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/scalar${CL} (Backend API)"
if pct exec "$CTID" -- test -d /opt/riven-frontend; then
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL} (Frontend UI)"
fi