#!/usr/bin/env bash

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build -f ${SCRIPT_DIR}/Dockerfile \
             -t ubuntu-24.04-dev:latest \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             --build-arg WORKDIR=$(pwd) \
             --build-arg RENDER_GID=$(getent group render | cut -d: -f3) \
             --build-arg VIDEO_GID=$(getent group video | cut -d: -f3) \
             .
