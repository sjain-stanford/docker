#!/usr/bin/env bash
set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize options for docker run
source "${SCRIPT_DIR}/init_docker.sh"

# Build docker image if not already built
source "${SCRIPT_DIR}/build_docker.sh"

docker run -it \
           ${DOCKER_RUN_MOUNT_OPTS} \
           ${DOCKER_RUN_DEVICE_OPTS} \
           ${DOCKER_RUN_BWRAP_OPTS} \
           ${DOCKER_RUN_ENV_OPTS} \
           -e THEROCK_GIT_TAG=${THEROCK_GIT_TAG:-} \
           -e AMD_ARCH=${AMD_ARCH:-} \
           --ulimit nofile=4096:4096 \
           compiler-dev-ubuntu-26.04:latest
