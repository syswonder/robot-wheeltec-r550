#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Wheeltec R550 mini_tank — full-stack bring-up script.
#
# Usage:
#   ./boot.sh              # build + boot
#   ./boot.sh --no-build   # skip build, boot only
#   ./boot.sh --shutdown   # tear down running stack
#   ./boot.sh --help
#
# Pre-requisites on the host (Jetson Orin + native ROS2):
#   - ROS 2 Humble (/opt/ros/humble/setup.bash)
#   - turn_on_wheeltec_robot ROS 2 workspace on the package path
#   - ros-humble-rtabmap-ros (apt install)
#   - ros-humble-imu-filter-madgwick (apt install)
#   - rbnx CLI on PATH
#   - VLM_* env vars exported (or set them in the block below)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── config ──────────────────────────────────────────────────────────────────
# Fill in your VLM credentials here, or pre-export in your shell rc.
: "${VLM_BASE_URL:=https://api.deepseek.com/v1}"
: "${VLM_API_KEY:=...}"
: "${VLM_MODEL:=deepseek-v4-pro}"
: "${TENCENTCLOUD_SECRET_ID:=...}"
: "${TENCENTCLOUD_SECRET_KEY:=...}"
export VLM_BASE_URL VLM_API_KEY VLM_MODEL TENCENTCLOUD_SECRET_ID TENCENTCLOUD_SECRET_KEY

# ROS 2 middleware — default to zenoh for better wireless/discovery performance.

# ROS 2 distro.
: "${ROS_DISTRO:=humble}"


# ── helpers ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[start]${NC} $*"; }
warn()  { echo -e "${YELLOW}[start]${NC} $*"; }
die()   { echo -e "${RED}[start] FATAL${NC} $*" >&2; exit 1; }

usage() {
  sed -n '2,/^$/s/^# //p' "$0"
  exit 0
}

# ── CLI ─────────────────────────────────────────────────────────────────────
BUILD=1
SHUTDOWN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)  BUILD=0; shift ;;
    --shutdown)  SHUTDOWN=1; shift ;;
    --help|-h)   usage ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

# ── shutdown path ───────────────────────────────────────────────────────────
if [[ "$SHUTDOWN" == "1" ]]; then
  info "shutting down…"
  rbnx shutdown -f "$SCRIPT_DIR/robonix_manifest.yaml" 2>/dev/null || true
  info "stopped."
  exit 0
fi

# ── pre-flight checks ───────────────────────────────────────────────────────
info "pre-flight checks…"

# rbnx CLI
command -v rbnx >/dev/null 2>&1 || die "rbnx not on PATH — install robonix-cli first"

# ROS 2
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
[[ -f "$ROS_SETUP" ]] || die "ROS 2 ${ROS_DISTRO} not found at ${ROS_SETUP}"
# shellcheck disable=SC1090

set +u
source "$ROS_SETUP"
set -u

# turn_on_wheeltec_robot
if ! ros2 pkg prefix turn_on_wheeltec_robot >/dev/null 2>&1; then
  die "turn_on_wheeltec_robot not on ROS package path — source your Wheeltec workspace first"
fi

# rtabmap + imu_filter (jetson-native mapping needs them on the host)
if ! ros2 pkg prefix rtabmap_slam >/dev/null 2>&1; then
  die "rtabmap_slam not found — run: sudo apt install ros-humble-rtabmap-ros"
fi
if ! ros2 pkg prefix imu_filter_madgwick >/dev/null 2>&1; then
  die "imu_filter_madgwick not found — run: sudo apt install ros-humble-imu-filter-madgwick"
fi

info "ROS ${ROS_DISTRO}  |  rbnx $(rbnx --version 2>/dev/null || echo ok)"
info "Wheeltec + rtabmap OK"


# ── boot ────────────────────────────────────────────────────────────────────
info "========== boot: full stack =========="
info "manifest: $SCRIPT_DIR/robonix_manifest.yaml"
info ""
info "  Boot order:"
info "    atlas → executor → pilot"
info "    robot_description → chassis → lidar"
info "    mapping (rtabmap)"
info ""
info "  Web UI:  http://<robot-ip>:8091"
info "  Chat:    rbnx chat"
info "  Caps:    rbnx caps"
info ""
# Default to rmw_zenoh_cpp for better wireless/discovery performance.
#export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_zenoh_cpp}"

# Start Zenoh router in background (required by rmw_zenoh_cpp for node discovery).
#info "starting Zenoh router…"
#ros2 run rmw_zenoh_cpp rmw_zenohd &
#ZENOH_PID=$!
# Give the router a moment to bind.
#sleep 2

exec rbnx boot -f "$SCRIPT_DIR/robonix_manifest.yaml"

