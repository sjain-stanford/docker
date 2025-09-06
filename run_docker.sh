#!/usr/bin/env bash

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build docker image if not already built
source "${SCRIPT_DIR}/build_docker.sh"

# Initialize options for docker run
source "${SCRIPT_DIR}/init_docker.sh"

# Bind mounts for the following:
# - current directory to same dir in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .cache etc)
docker run -it \
           ${DOCKER_RUN_DEVICE_OPTS} \
           -v "${PWD}":"${PWD}" \
           -v "${HOME}":"${HOME}" \
           compiler-dev-ubuntu-24.04:latest
