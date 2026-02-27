#!/usr/bin/env bash
set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build -f ${SCRIPT_DIR}/Dockerfile \
             -t compiler-dev-ubuntu-24.04:latest \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             --build-arg WORKDIR=$(pwd) \
             ${SCRIPT_DIR}
