#!/bin/bash
set -e

# Install dirs
# CAUTION: These directories need to be kept in sync with the `activate` script!!
DOCKER_CACHE_DIR=${PWD}/.cache/docker
VENV_DIR=${DOCKER_CACHE_DIR}/venv
THEROCK_DIR=${DOCKER_CACHE_DIR}/therock
IREE_DIR=${DOCKER_CACHE_DIR}/iree

# Version pins
IREE_GIT_TAG=3.9.0rc20251022
THEROCK_GIT_TAG=7.10.0a20251022
THEROCK_DIST=therock-dist-linux-gfx94X-dcgpu
THEROCK_TAR=${THEROCK_DIST}-${THEROCK_GIT_TAG}.tar.gz

# This installation is cached locally at `${PWD}/.cache/docker` so re-runs are
# instantaneous. However, the cache is NOT automatically invalidated and needs
# to be cleared manually (like when library versions are bumped). To clear the
# installation cache, simply remove the `${PWD}/.cache/docker` dir and re-run.
if [ ! -f "${DOCKER_CACHE_DIR}/.install_complete" ]; then
    echo "[entrypoint.sh] Cache NOT found at '${DOCKER_CACHE_DIR}', proceeding with installation..."
    mkdir -p ${DOCKER_CACHE_DIR}
    # Remove partial/corrupt cache contents that may have been
    # populated without a `.install_complete`.
    rm -rf ${DOCKER_CACHE_DIR}/*

    # Install TheRock (ROCm/HIP) for GFX942
    echo "[entrypoint.sh] Downloading TheRock (ROCm/HIP) prebuilt distribution '${THEROCK_DIST}' at tag '${THEROCK_GIT_TAG}'..."
    mkdir -p ${THEROCK_DIR}
    aria2c -x 16 -s 16 --max-tries=10 --retry-wait=5 \
           -d ${THEROCK_DIR} -o ${THEROCK_TAR} \
           https://therock-nightly-tarball.s3.us-east-2.amazonaws.com/${THEROCK_TAR}
    echo "[entrypoint.sh] Extracting TheRock (ROCm/HIP) prebuilt distribution..."
    tar -xf ${THEROCK_DIR}/${THEROCK_TAR} -C ${THEROCK_DIR}
    rm -f ${THEROCK_DIR}/${THEROCK_TAR}

    # Build IREE runtime from source
    echo "[entrypoint.sh] Building IREE runtime from source at tag '${IREE_GIT_TAG}'..."
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
    echo "[entrypoint.sh] Setting up python venv and installing pip deps..."
    python3 -m venv ${VENV_DIR}
    ${VENV_DIR}/bin/pip install \
        lit \
        --find-links https://iree.dev/pip-release-links.html \
        iree-base-compiler==${IREE_GIT_TAG}

    # Make FileCheck (from system llvm-18) and clang-20 (from TheRock) accessible in VENV
    ln -s /usr/lib/llvm-18/bin/FileCheck ${VENV_DIR}/bin/FileCheck
    ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-tidy ${VENV_DIR}/bin/clang-tidy
    ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-20 ${VENV_DIR}/bin/clang-20
    ln -s ${THEROCK_DIR}/lib/llvm/bin/clang-20 ${VENV_DIR}/bin/clang++-20
    ln -s ${VENV_DIR}/bin/clang-20 ${VENV_DIR}/bin/clang
    ln -s ${VENV_DIR}/bin/clang++-20 ${VENV_DIR}/bin/clang++

    # Used to validate cache for future runs
    touch "${DOCKER_CACHE_DIR}/.install_complete"

else
    echo "[entrypoint.sh] Cache found at '${DOCKER_CACHE_DIR}', skipped installation..."
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
