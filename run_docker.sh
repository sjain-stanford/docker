#!/usr/bin/env bash
set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build docker image if not already built
source "${SCRIPT_DIR}/build_docker.sh"

# Initialize options for docker run
source "${SCRIPT_DIR}/init_docker.sh"

docker run -it \
           ${DOCKER_RUN_MOUNT_OPTS} \
           ${DOCKER_RUN_DEVICE_OPTS} \
           -e IREE_GIT_TAG=${IREE_GIT_TAG:-} \
           -e THEROCK_GIT_TAG=${THEROCK_GIT_TAG:-} \
           -e AMD_ARCH=${AMD_ARCH:-} \
           --cap-drop=NET_RAW \
           --ulimit nofile=4096:4096 \
           compiler-dev-ubuntu-24.04:latest
