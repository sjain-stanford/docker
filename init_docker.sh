#!/usr/bin/env bash

# Bind mounts: only mount what the dev workflow actually needs.
# Sensitive paths (.bash_history, .docker) are intentionally excluded.
# Read-write mounts
DOCKER_RUN_MOUNT_OPTS="${DOCKER_RUN_MOUNT_OPTS:-}"
DOCKER_RUN_MOUNT_OPTS+=" -v ${PWD}:${PWD}"
[ -e "${HOME}/.claude" ]             && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.claude:${HOME}/.claude"
[ -e "${HOME}/.claude.json" ]        && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.claude.json:${HOME}/.claude.json"
[ -e "${HOME}/.codex" ]              && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.codex:${HOME}/.codex"
[ -e "${HOME}/.local/state/claude" ] && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.local/state/claude:${HOME}/.local/state/claude"
[ -e "${HOME}/.cache" ]              && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.cache:${HOME}/.cache"
[ -e "${HOME}/.cursor" ]             && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.cursor:${HOME}/.cursor"
[ -e "${HOME}/.cursor-server" ]      && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.cursor-server:${HOME}/.cursor-server"
# .bashrc is mounted read-write so `entrypoint.sh` can append its
# VENV-activation stanza (see entrypoint.sh).
[ -e "${HOME}/.bashrc" ]             && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bashrc:${HOME}/.bashrc"
# Read-only mounts
[ -e "${HOME}/.ssh" ]                && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.ssh:${HOME}/.ssh:ro"
[ -e "${HOME}/.gitconfig" ]          && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.gitconfig:${HOME}/.gitconfig:ro"
[ -e "${HOME}/.config" ]             && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.config:${HOME}/.config:ro"
[ -e "${HOME}/.gnupg" ]              && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.gnupg:${HOME}/.gnupg:ro"
[ -e "${HOME}/.local" ]              && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.local:${HOME}/.local:ro"
[ -e "${HOME}/.bash_aliases" ]       && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bash_aliases:${HOME}/.bash_aliases:ro"
[ -e "${HOME}/.bash_profile" ]       && DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bash_profile:${HOME}/.bash_profile:ro"

# ROCm requires accesses to the host’s /dev/kfd and /dev/dri/* device nodes, typically
# owned by the `render` and `video` groups. The groups’ GIDs in the container must
# match the host’s to access the resources. Sometimes the device nodes may be owned by
# dynamic GIDs (that don't belong to the `render` or `video` groups). So instead of
# adding user to the GIDs of named groups (obtained from `getent group render` or
# `getent group video`), we simply check the owning GID of the device nodes on the host
# and pass it to `docker run` with `--group-add=<GID>`.
DOCKER_RUN_DEVICE_OPTS="${DOCKER_RUN_DEVICE_OPTS:-}"
for DEV in /dev/kfd /dev/dri/*; do
  # Skip if not a character device
  # /dev/dri/by-path/ symlinks are ignored
  [[ -c "${DEV}" ]] || continue
  DOCKER_RUN_DEVICE_OPTS+=" --device=${DEV} --group-add=$(stat -c '%g' ${DEV})"
done

# Bubblewrap/Codex sandbox support:
# - bwrap runs as a setuid helper in the image for non-root container users.
# - Docker's default seccomp/AppArmor profiles can block namespace setup before
#   bwrap/Codex install their inner sandbox, so relax them explicitly here.
# - Mirrors https://github.com/openai/codex/blob/24be9ac0a4695274ac7921ecb692a9ffb3205fd2/.devcontainer/devcontainer.secure.json#L14
# Set DOCKER_ENABLE_BWRAP_SANDBOX=0 to launch without these runtime options.
DOCKER_RUN_BWRAP_OPTS="${DOCKER_RUN_BWRAP_OPTS:-}"
DOCKER_ENABLE_BWRAP_SANDBOX="${DOCKER_ENABLE_BWRAP_SANDBOX:-1}"
if [ "${DOCKER_ENABLE_BWRAP_SANDBOX}" = "1" ]; then
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=SYS_ADMIN"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=SYS_CHROOT"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=NET_ADMIN"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=NET_RAW"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=SETUID"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=SETGID"
  DOCKER_RUN_BWRAP_OPTS+=" --cap-add=SYS_PTRACE"
  DOCKER_RUN_BWRAP_OPTS+=" --security-opt=seccomp=unconfined"
  DOCKER_RUN_BWRAP_OPTS+=" --security-opt=apparmor=unconfined"
fi

# Export for use by `run_docker.sh`, `exec_docker.sh`, and `exec_docker_ci.sh`.
# `exec_docker_ci.sh` intentionally uses only device options from this file.
export DOCKER_RUN_MOUNT_OPTS
export DOCKER_RUN_DEVICE_OPTS
export DOCKER_RUN_BWRAP_OPTS
