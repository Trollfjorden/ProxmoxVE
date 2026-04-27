#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Trollfjorden/ProxmoxVE/feature/Riven/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rivenmedia/riven-ts

APP="RivenTSTest"
var_tags="${var_tags:-arr;media;debrid}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_fuse="${var_fuse:-yes}"
var_nesting="${var_nesting:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/rivents ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  msg_info "Checking for updates"
  RELEASE=$(git ls-remote https://github.com/rivenmedia/riven-ts.git chore/configure-multi-platform-docker-builds | awk '{ print $1 }')
  current=""
  [[ -f /opt/latest.txt ]] && current=$(cat /opt/latest.txt)

  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest commit hash from repository"
    exit
  fi

  if [[ "$RELEASE" != "$current" ]]; then
    msg_ok "Update available: ${current:-not installed} → ${RELEASE}"
    msg_info "Stopping Services"
    systemctl stop rivents postgresql redis-server
    msg_ok "Stopped Services"

    msg_info "Updating pnpm"
    PNPM_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/rivenmedia/riven-ts/refs/heads/chore/configure-multi-platform-docker-builds/package.json" | jq -r '.packageManager | split("@")[1]' | cut -d'+' -f1)"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack prepare pnpm@${PNPM_VERSION} --activate
    msg_ok "Updated pnpm"

    msg_info "Downloading RivenTS"
    $STD git clone -b chore/configure-multi-platform-docker-builds https://github.com/rivenmedia/riven-ts.git /opt/rivents.build
    echo "${RELEASE}" > /opt/latest.txt
    msg_ok "Downloaded RivenTS"

    msg_info "Building RivenTS"
    export NODE_OPTIONS="--max-old-space-size=4096"
    cd /opt/rivents.build
    $STD pnpm install --frozen-lockfile --force
    $STD pnpm turbo telemetry disable
    $STD pnpm turbo run build --no-daemon --filter=@repo/riven

    msg_info "Backing up Data"
    cp /opt/rivents/.env.riven /tmp/.env.riven 2>/dev/null || true
    msg_ok "Backed up Data"

    rm -rf /opt/rivents
    $STD pnpm --filter @repo/riven --prod deploy /opt/rivents
    cd /opt/rivents
    rm -rf /opt/rivents.build

    msg_info "Restoring Data"
    cp /tmp/.env.riven /opt/rivents/.env.riven 2>/dev/null || true
    msg_ok "Restored Data"
    msg_ok "Built RivenTS"
    
    msg_info "Starting Services"
    systemctl start postgresql redis-server rivents
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using its container IP:Port!${CL}"
