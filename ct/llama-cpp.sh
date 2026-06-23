#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Trollfjorden/ProxmoxVE/feature/Riven/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

APP="Llama.cpp"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/llama-cpp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f /opt/llama-cpp/.variant ]]; then
    msg_error "No variant configuration found! Please reinstall."
    exit
  fi

  local VARIANT
  VARIANT=$(cat /opt/llama-cpp/.variant)
  local ASSET_PATTERN
  case "$VARIANT" in
    cpu) ASSET_PATTERN="llama-*-bin-ubuntu-x64.tar.gz" ;;
    vulkan) ASSET_PATTERN="llama-*-bin-ubuntu-vulkan-x64.tar.gz" ;;
    openvino) ASSET_PATTERN="llama-*-bin-ubuntu-openvino-*-x64.tar.gz" ;;
    *)
      msg_error "Unknown variant: ${VARIANT}"
      exit
      ;;
  esac

  if check_for_gh_release "llama-cpp" "ggml-org/llama.cpp"; then
    msg_info "Stopping Service"
    systemctl stop llama-cpp
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    mkdir -p /opt/llama-cpp_backup
    cp -r /opt/llama-cpp/models /opt/llama-cpp_backup/
    cp /opt/llama-cpp/.variant /opt/llama-cpp_backup/
    cp /opt/llama-cpp/start.sh /opt/llama-cpp_backup/
    [[ -f /opt/llama-cpp/.openvino_version ]] && cp /opt/llama-cpp/.openvino_version /opt/llama-cpp_backup/
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$ASSET_PATTERN"

    msg_info "Restoring Data"
    cp -r /opt/llama-cpp_backup/models/. /opt/llama-cpp/models
    cp /opt/llama-cpp_backup/.variant /opt/llama-cpp/.variant
    cp /opt/llama-cpp_backup/start.sh /opt/llama-cpp/start.sh
    chmod +x /opt/llama-cpp/start.sh
    [[ -f /opt/llama-cpp_backup/.openvino_version ]] && cp /opt/llama-cpp_backup/.openvino_version /opt/llama-cpp/.openvino_version
    rm -rf /opt/llama-cpp_backup
    msg_ok "Restored Data"

    if [[ "$VARIANT" == "openvino" && -f /tmp/gh_rel.json ]]; then
      local NEW_OV_VER OLD_OV_VER=""
      NEW_OV_VER=$(jq -r '.assets[].name' /tmp/gh_rel.json 2>/dev/null | grep -oP 'openvino-\K[0-9]+\.[0-9]+' | head -1)
      [[ -f /opt/llama-cpp/.openvino_version ]] && OLD_OV_VER=$(cat /opt/llama-cpp/.openvino_version)
      if [[ -n "$NEW_OV_VER" && "$NEW_OV_VER" != "$OLD_OV_VER" ]]; then
        msg_info "Updating OpenVINO Runtime to ${NEW_OV_VER}"
        local OV_PKG
        OV_PKG=$(apt-cache pkgnames "openvino-${NEW_OV_VER}" 2>/dev/null | sort -V | tail -1)
        if [[ -n "$OV_PKG" ]]; then
          $STD apt install -y "$OV_PKG"
        else
          $STD apt install -y openvino
        fi
        echo "$NEW_OV_VER" >/opt/llama-cpp/.openvino_version
        msg_ok "Updated OpenVINO Runtime to ${NEW_OV_VER}"
      fi
    fi

    msg_info "Starting Service"
    systemctl start llama-cpp
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
