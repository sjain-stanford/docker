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
# https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html#accessing-gpus-in-containers
docker run -it \
           -v "${PWD}":"${PWD}" \
           -v "${HOME}":"${HOME}" \
           ${DOCKER_RUN_DEVICE_OPTS} \
           -e IREE_GIT_TAG=${IREE_GIT_TAG} \
           -e THEROCK_GIT_TAG=${THEROCK_GIT_TAG} \
           -e ARCH=${ARCH} \
           --security-opt seccomp=unconfined \
           compiler-dev-ubuntu-24.04:latest
