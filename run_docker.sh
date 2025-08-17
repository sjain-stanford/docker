#!/usr/bin/env bash

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build docker image if not already built
"${SCRIPT_DIR}/build_docker.sh"

# Bind mounts for the following:
# - current directory to same dir in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .cache etc)
docker run -it \
           --device /dev/kfd \
           --device /dev/dri \
           --security-opt seccomp=unconfined \
           -v "${PWD}":"${PWD}" \
           -v "${HOME}":"${HOME}" \
           ubuntu-24.04-dev:latest
