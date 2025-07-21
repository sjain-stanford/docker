#!/usr/bin/env bash

docker build -f docker/Dockerfile \
             -t main:dev \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             .

# If the target directory being volume mounted does not exist
# on the host, Docker will create it and that new directory will
# be owned by root by default, causing permission issues in the
# container. To mitigate this, create it on the host as non-root
# user to ensure correct permissions inside the container.
mkdir -p "${HOME}/.venv"
mkdir -p "${HOME}/.cache"

docker run -it \
           -v "$(pwd)":"/src" \
           -v "${HOME}/.bashrc":"${HOME}/.bashrc" \
           -v "${HOME}/.venv":"${HOME}/.venv" \
           -v "${HOME}/.cache":"${HOME}/.cache" \
           main:dev
