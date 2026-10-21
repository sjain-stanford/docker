#!/usr/bin/env bash

# Bind mounts: only mount what the dev workflow actually needs.
# Sensitive directories such as .docker are intentionally excluded.
DOCKER_RUN_MOUNT_OPTS="${DOCKER_RUN_MOUNT_OPTS:-}"
DOCKER_RUN_ENV_OPTS="${DOCKER_RUN_ENV_OPTS:-}"
DOCKER_RUN_PORT_OPTS="${DOCKER_RUN_PORT_OPTS:-}"

mount_home_state_file() {
  local path="${HOME}/$1"
  local initial_content="$2"
  if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
    # Never truncate an existing file, including during concurrent launches.
    (umask 077; set -o noclobber; printf '%s' "${initial_content}" > "${path}") || return 1
  fi
  if [ ! -f "${path}" ]; then
    echo "ERROR: Expected a regular state file: ${path}" >&2
    return 1
  fi
  DOCKER_RUN_MOUNT_OPTS+=" -v ${path}:${path}"
}

# Only local launchers call this; CI does not use home mounts.
init_docker_home_mounts() {
  local path
  DOCKER_RUN_MOUNT_OPTS+=" -v ${PWD}:${PWD}"

  # Create writable state on the host before Docker can create root-owned
  # mount sources or applications can leave state only in the container.
  # A private umask also protects newly created parents of nested state paths.
  for path in .claude .codex .local/state/claude .cache .cursor .cursor-server .config/cursor; do
    (umask 077; mkdir -p -m 700 "${HOME}/${path}") || return 1
    DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/${path}:${HOME}/${path}"
  done
  mount_home_state_file .claude.json $'{}\n' || return 1
  mount_home_state_file .bash_history '' || return 1

  # Import an existing shell configuration read-write for entrypoint.sh's
  # VENV stanza. An empty placeholder would hide the image's default .bashrc.
  if [ -e "${HOME}/.bashrc" ]; then
    DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/.bashrc:${HOME}/.bashrc"
  fi

  # Optional host configuration stays read-only. The writable child mounts
  # let Claude save state under ~/.local and Cursor save tokens under ~/.config.
  for path in .ssh .gitconfig .config .gnupg .local .bash_aliases .bash_profile; do
    if [ -e "${HOME}/${path}" ]; then
      DOCKER_RUN_MOUNT_OPTS+=" -v ${HOME}/${path}:${HOME}/${path}:ro"
    fi
  done
}

# Peanut-review web UI forwarding.
# VSCode Remote SSH can only discover ports listening on the SSH host, not
# ports isolated in the container's network namespace. Opt in to publishing a
# fixed container port on the host's loopback interface so VSCode can forward
# it without exposing the web UI on the host's external interfaces.
DOCKER_ENABLE_PEANUT_REVIEW_WEB="${DOCKER_ENABLE_PEANUT_REVIEW_WEB:-0}"
PEANUT_REVIEW_PORT="${PEANUT_REVIEW_PORT:-27183}"
if [ "${DOCKER_ENABLE_PEANUT_REVIEW_WEB}" = "1" ]; then
  echo "WARNING: Peanut-review has no web UI authentication." >&2
  echo "Only enable port forwarding on a single-user or fully trusted SSH host." >&2
  if ! [[ "${PEANUT_REVIEW_PORT}" =~ ^[0-9]{1,5}$ ]] \
      || (( 10#${PEANUT_REVIEW_PORT} < 1 || 10#${PEANUT_REVIEW_PORT} > 65535 )); then
    echo "ERROR: PEANUT_REVIEW_PORT must be an integer from 1 through 65535" >&2
    exit 1
  fi
  PEANUT_REVIEW_PORT=$((10#${PEANUT_REVIEW_PORT}))
  DOCKER_RUN_PORT_OPTS+=" -p 127.0.0.1:${PEANUT_REVIEW_PORT}:${PEANUT_REVIEW_PORT}"
  DOCKER_RUN_ENV_OPTS+=" -e PEANUT_REVIEW_PORT=${PEANUT_REVIEW_PORT}"
fi

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

# ROCm requires access to the host's /dev/kfd and /dev/dri/* device nodes, typically
# owned by the `render` and `video` groups. Set DOCKER_ENABLE_AMD_GPU=0 to omit these
# mappings, for example when testing rocjitsu with only simulated GPUs visible.
#
# When GPU access is enabled, use the owning GIDs of the device nodes instead of the
# named groups because some hosts assign dynamic GIDs.
DOCKER_RUN_DEVICE_OPTS="${DOCKER_RUN_DEVICE_OPTS:-}"
DOCKER_ENABLE_AMD_GPU="${DOCKER_ENABLE_AMD_GPU:-1}"
if [ "${DOCKER_ENABLE_AMD_GPU}" = "1" ]; then
  for DEV in /dev/kfd /dev/dri/*; do
    # Skip non-character devices, including /dev/dri/by-path symlinks.
    [[ -c "${DEV}" ]] || continue
    DOCKER_RUN_DEVICE_OPTS+=" --device=${DEV} --group-add=$(stat -c '%g' "${DEV}")"
  done
fi

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
export DOCKER_RUN_PORT_OPTS
export DOCKER_RUN_DEVICE_OPTS
export DOCKER_RUN_BWRAP_OPTS
