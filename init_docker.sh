#!/usr/bin/env bash

# Bind mounts: only mount what the dev workflow actually needs.
# Sensitive paths (.bash_history, .docker) are intentionally excluded.
# Read-write mounts
DOCKER_RUN_MOUNT_OPTS="${DOCKER_RUN_MOUNT_OPTS:-}"
DOCKER_RUN_ENV_OPTS="${DOCKER_RUN_ENV_OPTS:-}"
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

# Host Docker API compatibility.
# Export the host daemon API version before running host-side docker commands
# from run_docker.sh and exec_docker.sh, even when socket forwarding is disabled.
detect_host_docker_api_version() {
  local api_version
  api_version="$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || true)"
  if [ -n "${api_version}" ]; then
    printf "%s\n" "${api_version}"
    return
  fi

  docker version 2>&1 \
    | sed -n 's/.*Maximum supported API version is \([0-9][0-9.]*\).*/\1/p' \
    | tail -n 1 || true
}

HOST_DOCKER_API_VERSION="${DOCKER_API_VERSION:-}"
if [ -z "${HOST_DOCKER_API_VERSION}" ]; then
  HOST_DOCKER_API_VERSION="$(detect_host_docker_api_version)"
fi
if [ -n "${HOST_DOCKER_API_VERSION}" ]; then
  export DOCKER_API_VERSION="${HOST_DOCKER_API_VERSION}"
fi

# Host Docker socket forwarding.
# This uses the host Docker daemon from inside the dev container, so containers
# launched from the dev container are host-level sibling containers.
# Set DOCKER_ENABLE_HOST_DOCKER=1 to launch with host Docker access.
DOCKER_ENABLE_HOST_DOCKER="${DOCKER_ENABLE_HOST_DOCKER:-0}"
if [ "${DOCKER_ENABLE_HOST_DOCKER}" = "1" ] && [ -S /var/run/docker.sock ]; then
  DOCKER_RUN_MOUNT_OPTS+=" -v /var/run/docker.sock:/var/run/docker.sock"
  DOCKER_RUN_MOUNT_OPTS+=" --group-add=$(stat -c '%g' /var/run/docker.sock)"

  if [ -n "${HOST_DOCKER_API_VERSION}" ]; then
    DOCKER_RUN_ENV_OPTS+=" -e DOCKER_API_VERSION=${HOST_DOCKER_API_VERSION}"
  fi
fi

# AMD GPU architecture selection.
# If the user does not set AMD_ARCH explicitly, detect the first host GPU
# reported by ROCm and map it to the matching TheRock distribution family.
detect_host_amd_arch() {
  local arch
  arch=""

  if command -v rocminfo >/dev/null 2>&1; then
    arch="$(awk '/^[[:space:]]*Name:[[:space:]]*gfx/ { print $2; exit }' < <(rocminfo 2>/dev/null) || true)"
  fi

  case "${arch}" in
    gfx94[0-9])
      printf "%s\n" "gfx94X"
      ;;
    gfx950)
      printf "%s\n" "gfx950"
      ;;
    gfx110[0-9])
      printf "%s\n" "gfx110X"
      ;;
    gfx120[0-9])
      printf "%s\n" "gfx120X"
      ;;
  esac
}

if [ -z "${AMD_ARCH:-}" ]; then
  AMD_ARCH="$(detect_host_amd_arch)"
fi
export AMD_ARCH

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
export DOCKER_RUN_ENV_OPTS
export DOCKER_RUN_DEVICE_OPTS
export DOCKER_RUN_BWRAP_OPTS
