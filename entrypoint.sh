#!/bin/bash
set -euo pipefail

# Install dirs
# CAUTION: These directories need to be kept in sync with the `activate` script!!
DOCKER_CACHE_DIR=${PWD}/.cache/docker
VENV_DIR=${DOCKER_CACHE_DIR}/venv
THEROCK_DIR=${DOCKER_CACHE_DIR}/therock
IREE_DIR=${DOCKER_CACHE_DIR}/iree

# Version pins
IREE_GIT_TAG="${IREE_GIT_TAG:-3.11.0rc20260217}"
THEROCK_GIT_TAG="${THEROCK_GIT_TAG:-7.12.0a20260217}"
AMD_ARCH="${AMD_ARCH:-gfx94X}"

case "$AMD_ARCH" in
  gfx94X | gfx942)
    THEROCK_DIST="therock-dist-linux-gfx94X-dcgpu"
    ;;
  gfx950)
    THEROCK_DIST="therock-dist-linux-gfx950-dcgpu"
    ;;
  gfx110X | gfx1100)
    THEROCK_DIST="therock-dist-linux-gfx110X-all"
    ;;
  gfx120X | gfx1201)
    THEROCK_DIST="therock-dist-linux-gfx120X-all"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $AMD_ARCH" >&2
    exit 1
    ;;
esac

THEROCK_TAR=${THEROCK_DIST}-${THEROCK_GIT_TAG}.tar.gz

# This installation is cached locally at `${PWD}/.cache/docker` so re-runs are
# instantaneous. The cache is automatically invalidated when IREE or TheRock
# versions change (the cache marker encodes version pins). To force a clean
# reinstall, remove the `${PWD}/.cache/docker` dir and re-run.
CACHE_KEY="${IREE_GIT_TAG}-${THEROCK_GIT_TAG}"
if [ ! -f "${DOCKER_CACHE_DIR}/.install_complete_${CACHE_KEY}" ]; then
    echo "[entrypoint.sh] Cache NOT found for '${CACHE_KEY}' at '${DOCKER_CACHE_DIR}', proceeding with installation..."
    # Remove stale cache (including old .install_complete markers and
    # partial/corrupt contents from interrupted installs).
    rm -rf ${DOCKER_CACHE_DIR}/*
    mkdir -p ${DOCKER_CACHE_DIR}

    # Install TheRock (ROCm/HIP) for GFX942
    echo "[entrypoint.sh] Downloading TheRock (ROCm/HIP) prebuilt distribution '${THEROCK_DIST}' at tag '${THEROCK_GIT_TAG}'..."
    mkdir -p ${THEROCK_DIR}
    aria2c -x 16 -s 16 --max-tries=10 --retry-wait=5 \
           -d ${THEROCK_DIR} -o ${THEROCK_TAR} \
           https://therock-nightly-tarball.s3.us-east-2.amazonaws.com/${THEROCK_TAR}
    echo "[entrypoint.sh] Extracting TheRock (ROCm/HIP) prebuilt distribution..."
    tar -xf ${THEROCK_DIR}/${THEROCK_TAR} -C ${THEROCK_DIR}
    rm -f ${THEROCK_DIR}/${THEROCK_TAR}

    # Clone IREE source
    echo "[entrypoint.sh] Fetching IREE from source at tag '${IREE_GIT_TAG}'..."
    git clone --depth=1 --branch iree-${IREE_GIT_TAG} https://github.com/iree-org/iree.git ${IREE_DIR}
    # Run this in a subshell to preserve $(pwd) for main shell
    (
        cd ${IREE_DIR}
        git submodule update --init \
            third_party/hip-build-deps \
            third_party/benchmark \
            third_party/flatcc
    )

    # Install python virtual env and dependencies
    echo "[entrypoint.sh] Setting up python venv and installing pip deps..."
    python3 -m venv ${VENV_DIR}
    ${VENV_DIR}/bin/pip install \
        lit \
        --find-links https://iree.dev/pip-release-links.html \
        iree-base-compiler==${IREE_GIT_TAG}

    # Make FileCheck (from system llvm-18) and clang-22, llvm-symbolizer (from TheRock) accessible in VENV
    ln -s /usr/lib/llvm-18/bin/FileCheck ${VENV_DIR}/bin/FileCheck
    # TODO(sjain-stanford): clang-tidy from TheRock segfaults. Use system clang-tidy instead.
    # ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-tidy ${VENV_DIR}/bin/clang-tidy
    ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-22 ${VENV_DIR}/bin/clang-22
    ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-22 ${VENV_DIR}/bin/clang++-22
    ln -s ${VENV_DIR}/bin/clang-22 ${VENV_DIR}/bin/clang
    ln -s ${VENV_DIR}/bin/clang++-22 ${VENV_DIR}/bin/clang++
    ln -s ${THEROCK_DIR}/lib/llvm/bin/llvm-symbolizer ${VENV_DIR}/bin/llvm-symbolizer-22
    ln -s ${VENV_DIR}/bin/llvm-symbolizer-22 ${VENV_DIR}/bin/llvm-symbolizer

    # Used to validate cache for future runs
    touch "${DOCKER_CACHE_DIR}/.install_complete_${CACHE_KEY}"

else
    echo "[entrypoint.sh] Cache found for '${CACHE_KEY}' at '${DOCKER_CACHE_DIR}', skipped installation..."
fi

# Check if stdin is attached to a TTY (true for interactive run, false otherwise).
if [ -t 0 ]; then
    # Set PATH and LD_LIBRARY_PATH for interactive shells via `.bashrc`.
    # This is useful for local development (`run_docker.sh`) and VSCode's dev-containers.
    BASHRC_FILE="${HOME}/.bashrc"
    MARKER="# [Compiler Docker] Source VENV for PATH and LD_LIBRARY_PATH changes"
    if ! grep -qF -- "${MARKER}" "${BASHRC_FILE}" 2>/dev/null; then
        echo "[entrypoint.sh] Interactive docker: Adding VENV source activate to '${BASHRC_FILE}'..."
        {
            echo -e "\n${MARKER}"
            echo "if [ -f /usr/local/bin/activate ]; then"
            # This path is being cached here for supporting the VSCode Dev Container workflows
            # where a container is launched once (triggering the bashrc update), and then attached
            # to from different workspaces (and working directories). In such a scenario, the
            # docker cache is populated at ${PWD} from the first container launch, and reused in
            # subsequent workspaces through the cached path in the `.bashrc`.
            echo "    DOCKER_CACHE_BASE_DIR=\"${PWD}\""
            echo "    source /usr/local/bin/activate \${DOCKER_CACHE_BASE_DIR}"
            echo "fi"
        } >> "${BASHRC_FILE}"
    else
        echo "[entrypoint.sh] Interactive docker: Found VENV source activate in '${BASHRC_FILE}', skipped editing..."
    fi
else
  # Set PATH and LD_LIBRARY_PATH for non-interactive shells via direct `source activate`.
  # This is useful for batch runs (`exec_docker.sh`) and CI (`exec_docker_ci.sh`).
  echo "[entrypoint.sh] Non-interactive docker: Sourcing VENV activate now..."
  source /usr/local/bin/activate ${PWD}
fi

# Execute the command passed to the container
exec "$@"
