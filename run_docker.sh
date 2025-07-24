#!/usr/bin/env bash

docker build -f docker/Dockerfile \
             -t main:dev \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             --build-arg PWD=$(pwd) \
             .

# Bind mounts for the following:
# - current directory to same dir in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .venv, .cache etc)
docker run -it \
           -v "${PWD}":"${PWD}" \
           -v "${HOME}":"${HOME}" \
           main:dev
