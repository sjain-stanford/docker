#!/usr/bin/env bash

docker build -f docker/Dockerfile \
             -t sjainstanford/ubuntu-24.04-dev:latest \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             --build-arg WORKDIR=/src \
             .

docker push sjainstanford/ubuntu-24.04-dev:latest

# Bind mounts for the following:
# - current directory to /src in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .venv, .cache etc)
# docker run -it \
#            -v "${PWD}":"/src" \
#            -v "${HOME}":"${HOME}" \
#            sjainstanford/ubuntu-24.04-dev:latest
