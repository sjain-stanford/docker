#!/usr/bin/env bash

# Bind mounts: only mount what the dev workflow actually needs.
# Sensitive paths (.bash_history, .docker) are intentionally excluded.
# Read-write mounts
DOCKER_RUN_MOUNT_OPTS=""
DOCKER_RUN_MOUNT_OPTS+=" -v ${PWD}:${PWD}"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.claude:${HOME}/.claude"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.claude.json:${HOME}/.claude.json"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.cache:${HOME}/.cache"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.cursor-server:${HOME}/.cursor-server"
# Read-only mounts
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.ssh:${HOME}/.ssh:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.gitconfig:${HOME}/.gitconfig:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.config:${HOME}/.config:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.gnupg:${HOME}/.gnupg:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.local:${HOME}/.local:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bashrc:${HOME}/.bashrc:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bash_aliases:${HOME}/.bash_aliases:ro"
DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bash_profile:${HOME}/.bash_profile:ro"

# ROCm requires accesses to the host’s /dev/kfd and /dev/dri/* device nodes, typically
# owned by the `render` and `video` groups. The groups’ GIDs in the container must
# match the host’s to access the resources. Sometimes the device nodes may be owned by
# dynamic GIDs (that don't belong to the `render` or `video` groups). So instead of
# adding user to the GIDs of named groups (obtained from `getent group render` or
# `getent group video`), we simply check the owning GID of the device nodes on the host
# and pass it to `docker run` with `--group-add=<GID>`.
DOCKER_RUN_DEVICE_OPTS=""
for DEV in /dev/kfd /dev/dri/*; do
  # Skip if not a character device
  # /dev/dri/by-path/ symlinks are ignored
  [[ -c "${DEV}" ]] || continue
  DOCKER_RUN_DEVICE_OPTS+=" --device=${DEV} --group-add=$(stat -c '%g' ${DEV})"
done

# Export for use by `run_docker.sh` and `exec_docker.sh`
export DOCKER_RUN_MOUNT_OPTS
export DOCKER_RUN_DEVICE_OPTS
