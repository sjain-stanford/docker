#!/usr/bin/env bash

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build docker image if not already built
"${SCRIPT_DIR}/build_docker.sh"

# ROCm requires accesses to the host’s /dev/kfd and /dev/dri/* device nodes owned
# by the `render` and `video` groups. The groups’ GIDs in the container must match
# the host’s to access the resources. Sometimes the device nodes may be owned by
# dynamic GIDs (that don't belong to the `render` or `video` groups). So instead of
# adding user to the named groups (using `getent group render` or `getent group video`)
# we simply check the owning GID of the devices and pass it to the `docker run`.
for DEV in /dev/kfd /dev/dri/*; do
  # Skip if not a character device
  # /dev/dri/by-path/ symlinks are ignored
  [[ -c "$DEV" ]] || continue
  DEVICE_GROUP_OPTS+=" --device=$DEV --group-add=$(stat -c '%g' $DEV)"
done

# Bind mounts for the following:
# - current directory to same dir in the container
# - user's HOME directory (useful for .bash*, .gitconfig, .cache etc)
docker run --rm \
           ${DEVICE_GROUP_OPTS} \
           -v "${PWD}":"${PWD}" \
           -v "${HOME}":"${HOME}" \
           ubuntu-24.04-dev:latest \
           "$@"
