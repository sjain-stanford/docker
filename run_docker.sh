#!/usr/bin/env bash

docker build -f docker/Dockerfile \
             -t main:dev \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             .

# Bind mounts for the following:
# - current directory to /src in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .venv, .cache etc)
docker run -it \
           -v "$(pwd)":"/src" \
           -v "${HOME}":"${HOME}" \
           main:dev
