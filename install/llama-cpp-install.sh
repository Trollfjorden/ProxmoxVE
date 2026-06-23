#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trollfjorden
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─────────────────────────────────────────────────────────────────────────────
# Variant Selection
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "  Select llama.cpp backend variant:"
echo ""
echo "    1) CPU       - No GPU required, pure CPU inference"
echo "    2) Vulkan    - Intel iGPU acceleration via Vulkan API"
echo "    3) OpenVINO  - Intel iGPU acceleration via OpenVINO runtime"
echo ""
VARIANT_CHOICE=""
read -r -t 120 -p "  Select variant [1-3] (default=1, timeout 120s): " VARIANT_CHOICE || VARIANT_CHOICE="1"
case "${VARIANT_CHOICE:-1}" in
  2) VARIANT="vulkan" ;;
  3) VARIANT="openvino" ;;
  *) VARIANT="cpu" ;;
esac
mkdir -p /opt/llama-cpp
echo "$VARIANT" >/opt/llama-cpp/.variant
msg_ok "Selected backend: ${VARIANT}"

# ─────────────────────────────────────────────────────────────────────────────
# Variant-Specific Dependencies
# ─────────────────────────────────────────────────────────────────────────────
case "$VARIANT" in
  vulkan)
    msg_info "Installing Vulkan Dependencies"
    $STD apt install -y \
      libvulkan1 \
      mesa-vulkan-drivers \
      vulkan-tools
    msg_ok "Installed Vulkan Dependencies"
    ;;
  openvino)
    msg_info "Setting up Intel OpenVINO Repository"
    $STD apt install -y jq
    mkdir -p /usr/share/keyrings
    curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB |
      gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg 2>/dev/null || true
    cat <<EOF >/etc/apt/sources.list.d/intel-openvino.sources
Types: deb
URIs: https://apt.repos.intel.com/openvino
Suites: ubuntu24
Components: main
Signed-By: /usr/share/keyrings/oneapi-archive-keyring.gpg
EOF
    $STD apt update
    msg_ok "Set up Intel OpenVINO Repository"
    ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Download llama.cpp Pre-built Binary
# ─────────────────────────────────────────────────────────────────────────────
case "$VARIANT" in
  cpu) ASSET_PATTERN="llama-*-bin-ubuntu-x64.tar.gz" ;;
  vulkan) ASSET_PATTERN="llama-*-bin-ubuntu-vulkan-x64.tar.gz" ;;
  openvino) ASSET_PATTERN="llama-*-bin-ubuntu-openvino-*-x64.tar.gz" ;;
esac

fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$ASSET_PATTERN"

# ─────────────────────────────────────────────────────────────────────────────
# OpenVINO Runtime (version matched to release asset)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$VARIANT" == "openvino" ]]; then
  msg_info "Installing OpenVINO Runtime"
  OV_VER=""
  if [[ -f /tmp/gh_rel.json ]]; then
    OV_VER=$(jq -r '.assets[].name' /tmp/gh_rel.json 2>/dev/null | grep -oP 'openvino-\K[0-9]+\.[0-9]+' | head -1)
  fi
  if [[ -n "$OV_VER" ]]; then
    OV_PKG=$(apt-cache pkgnames "openvino-${OV_VER}" 2>/dev/null | sort -V | tail -1)
    if [[ -n "$OV_PKG" ]]; then
      $STD apt install -y "$OV_PKG"
    else
      msg_warn "OpenVINO ${OV_VER} not found in APT, installing latest available"
      $STD apt install -y openvino
    fi
    echo "$OV_VER" >/opt/llama-cpp/.openvino_version
  else
    msg_warn "Could not determine OpenVINO version from release, installing latest available"
    $STD apt install -y openvino
  fi
  msg_ok "Installed OpenVINO Runtime"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Model Download Prompt
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p /opt/llama-cpp/models
echo ""
msg_custom "🤖" "${GN}" "Model Setup"
echo ""
echo "  Provide a direct URL to a GGUF model file."
echo "  Example: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
echo ""
MODEL_URL=""
read -r -t 120 -p "  Model URL (leave empty to skip): " MODEL_URL || MODEL_URL=""

if [[ -n "$MODEL_URL" ]]; then
  MODEL_FILE=$(basename "$MODEL_URL")
  msg_info "Downloading Model: ${MODEL_FILE} (Patience)"
  if $STD curl -fSL -o "/opt/llama-cpp/models/${MODEL_FILE}" "$MODEL_URL"; then
    msg_ok "Downloaded Model: ${MODEL_FILE}"
  else
    rm -f "/opt/llama-cpp/models/${MODEL_FILE}"
    msg_warn "Model download failed. Add GGUF models to /opt/llama-cpp/models/ manually."
  fi
else
  msg_info "No model URL provided. Add GGUF models to /opt/llama-cpp/models/ later."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Startup Script
# ─────────────────────────────────────────────────────────────────────────────
cat <<'STARTEOF' >/opt/llama-cpp/start.sh
#!/bin/bash
MODEL_DIR="/opt/llama-cpp/models"
MODEL=$(find "$MODEL_DIR" -maxdepth 1 -name "*.gguf" -type f 2>/dev/null | head -1)

if [[ -z "$MODEL" ]]; then
  echo "WARNING: No .gguf model found in $MODEL_DIR" >&2
  echo "Download a model and restart the service:" >&2
  echo "  curl -L -o $MODEL_DIR/model.gguf <huggingface-url>" >&2
  echo "  systemctl restart llama-cpp" >&2
  exit 1
fi

# Locate llama-server binary (path depends on tarball structure)
if [[ -x /opt/llama-cpp/llama-server ]]; then
  LLAMA_SERVER=/opt/llama-cpp/llama-server
  LIB_DIR=/opt/llama-cpp
else
  echo "ERROR: llama-server binary not found!" >&2
  exit 1
fi

export LD_LIBRARY_PATH="${LIB_DIR}:${LD_LIBRARY_PATH:-}"

# Source OpenVINO environment if variant is openvino
if [[ -f /opt/llama-cpp/.variant ]] && [[ "$(cat /opt/llama-cpp/.variant)" == "openvino" ]]; then
  if [[ -f /opt/intel/openvino/setupvars.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/intel/openvino/setupvars.sh
  elif [[ -f /usr/share/openvino/setupvars.sh ]]; then
    # shellcheck disable=SC1091
    source /usr/share/openvino/setupvars.sh
  fi
fi

exec "$LLAMA_SERVER" \
  --host 0.0.0.0 \
  --port 8080 \
  --model "$MODEL"
STARTEOF
chmod +x /opt/llama-cpp/start.sh

# ─────────────────────────────────────────────────────────────────────────────
# Systemd Service
# ─────────────────────────────────────────────────────────────────────────────
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/llama-cpp.service
[Unit]
Description=llama.cpp Server
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llama-cpp
ExecStart=/opt/llama-cpp/start.sh
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now llama-cpp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
