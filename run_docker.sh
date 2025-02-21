#!/usr/bin/env bash

docker build -f docker/Dockerfile \
             -t main:dev \
             --build-arg GROUP=$(id -gn) \
             --build-arg GID=$(id -g) \
             --build-arg USER=$(id -un) \
             --build-arg UID=$(id -u) \
             .

docker run -it \
           -v "$(pwd)":"/src" \
           -v "${HOME}/.bashrc":"${HOME}/.bashrc" \
           -v "${HOME}/.cache":"${HOME}/.cache" \
           main:dev
