#!/usr/bin/env bash

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize options for docker run
source "${SCRIPT_DIR}/init_docker.sh"

# Bind mounts for the following:
# - current directory to /workspace in the container
# https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html#accessing-gpus-in-containers
chmod +x "$SCRIPT_DIR/entrypoint.sh"

docker run --rm \
           -v "${PWD}":/workspace \
           ${DOCKER_RUN_DEVICE_OPTS} \
           -e IREE_GIT_TAG=${IREE_GIT_TAG} \
           -e THEROCK_GIT_TAG=${THEROCK_GIT_TAG} \
           -e AMD_ARCH=${AMD_ARCH} \
           -v "$SCRIPT_DIR/entrypoint.sh:/entrypoint.sh" \
           --entrypoint /entrypoint.sh \
           --security-opt seccomp=unconfined \
           ghcr.io/sjain-stanford/compiler-dev-ubuntu-24.04:main \
           "$@"
