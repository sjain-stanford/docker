#!/usr/bin/env bash

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize options for docker run
source "${SCRIPT_DIR}/init_docker.sh"

# Bind mounts for the following:
# - current directory to /workspace in the container
docker run --rm \
           ${DOCKER_RUN_DEVICE_OPTS} \
           -v "${PWD}":/workspace \
           ghcr.io/sjain-stanford/compiler-dev-ubuntu-24.04:main \
           "$@"
