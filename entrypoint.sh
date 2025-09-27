#!/bin/bash
set -e

# Install dirs
# CAUTION: These directories need to be kept in sync with the `activate` script!!
DOCKER_CACHE_DIR=${PWD}/.cache/docker
VENV_DIR=${DOCKER_CACHE_DIR}/venv
THEROCK_DIR=${DOCKER_CACHE_DIR}/therock
IREE_DIR=${DOCKER_CACHE_DIR}/iree

# Version pins
IREE_GIT_TAG=3.8.0rc20250922
THEROCK_GIT_TAG=7.0.0rc20250922
THEROCK_DIST=therock-dist-linux-gfx94X-dcgpu
THEROCK_TAR=${THEROCK_DIST}-${THEROCK_GIT_TAG}.tar.gz

# This installation is cached locally at `${PWD}/.cache/docker` so re-runs are
# instantaneous. However, the cache is NOT automatically invalidated and needs
# to be cleared manually (like when library versions are bumped). To clear the
# installation cache, simply remove the `${PWD}/.cache/docker` dir and re-run.
if [ ! -f "${DOCKER_CACHE_DIR}/.install_complete" ]; then
    echo "entrypoint.sh: Cache NOT found at ${DOCKER_CACHE_DIR}, proceeding with installation..."
    mkdir -p ${DOCKER_CACHE_DIR}
    # Remove partial/corrupt cache contents that may have been
    # populated without a `.install_complete`.
    rm -rf ${DOCKER_CACHE_DIR}/*

    # Install TheRock (ROCm/HIP) for GFX942
    echo "entrypoint.sh: Downloading TheRock (ROCm/HIP) prebuilt distribution for GFX942..."
    mkdir -p ${THEROCK_DIR}
    aria2c -x 16 -s 16 -d ${THEROCK_DIR} -o ${THEROCK_TAR} \
        https://therock-nightly-tarball.s3.us-east-2.amazonaws.com/${THEROCK_TAR}
    echo "entrypoint.sh: Extracting TheRock (ROCm/HIP) prebuilt distribution for GFX942..."
    tar -xf ${THEROCK_DIR}/${THEROCK_TAR} -C ${THEROCK_DIR}
    rm -f ${THEROCK_DIR}/${THEROCK_TAR}

    # Build IREE runtime from source
    echo "entrypoint.sh: Building IREE runtime from source..."
    git clone --depth=1 --branch iree-${IREE_GIT_TAG} https://github.com/iree-org/iree.git ${IREE_DIR}
    # Run this in a subshell to preserve $(pwd) for main shell
    (
        cd ${IREE_DIR}
        git submodule update --init \
            third_party/hip-build-deps \
            third_party/cpuinfo \
            third_party/benchmark \
            third_party/flatcc
        cmake -G Ninja -B build -S . \
            -DIREE_VISIBILITY_HIDDEN=OFF \
            -DIREE_BUILD_COMPILER=OFF \
            -DIREE_BUILD_TESTS=OFF \
            -DIREE_BUILD_SAMPLES=OFF \
            -DIREE_ERROR_ON_MISSING_SUBMODULES=OFF \
            -DIREE_HAL_DRIVER_DEFAULTS=OFF \
            -DIREE_HAL_DRIVER_LOCAL_SYNC=ON \
            -DIREE_HAL_DRIVER_LOCAL_TASK=ON \
            -DIREE_HAL_DRIVER_HIP=ON \
            -DHIP_API_HEADERS_ROOT=${THEROCK_DIR}/include
        cmake --build build --target all
    )

    # Install python virtual env and dependencies
    echo "entrypoint.sh: Setting up python venv and installing pip deps..."
    python3 -m venv ${VENV_DIR}
    source /usr/local/bin/activate
    pip install \
        lit \
        --find-links https://iree.dev/pip-release-links.html \
        iree-base-compiler==${IREE_GIT_TAG}
    deactivate

    # Used to validate cache for future runs
    touch "${DOCKER_CACHE_DIR}/.install_complete"

else
    echo "entrypoint.sh: Cache found at ${DOCKER_CACHE_DIR}, skipped installation..."
fi

# Check if stdin is attached to a TTY (true for interactive run, false otherwise).
if [ -t 0 ]; then
    # Set PATH and LD_LIBRARY_PATH for interactive shells via `.bashrc`.
    # This is useful for local development (`run_docker.sh`) and VSCode's dev-containers.
    BASHRC_FILE="${HOME}/.bashrc"
    MARKER="# [Compiler Docker] Source VENV for PATH and LD_LIBRARY_PATH changes"
    if ! grep -qF -- "${MARKER}" "${BASHRC_FILE}" 2>/dev/null; then
        echo "entrypoint.sh: Interactive docker: Adding VENV source activate to ${BASHRC_FILE}"
        {
            echo -e "\n${MARKER}"
            echo "if [ -f /usr/local/bin/activate ]; then"
            echo "    source /usr/local/bin/activate"
            echo "fi"
        } >> "${BASHRC_FILE}"
    else
        echo "entrypoint.sh: Interactive docker: Found VENV source activate in ${BASHRC_FILE}, skipped editing..."
    fi
else
  # Set PATH and LD_LIBRARY_PATH for non-interactive shells via direct `source activate`.
  # This is useful for batch runs (`exec_docker.sh`) and CI (`exec_docker_ci.sh`).
  echo "entrypoint.sh: Non-interactive docker: Sourcing VENV activate now..."
  source /usr/local/bin/activate
fi

# Execute the command passed to the container
exec "$@"
