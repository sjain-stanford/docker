#!/bin/bash
set -e

# Install dirs
CACHE_DIR=${HOME}/.cache/docker
THEROCK_DIR=${CACHE_DIR}/therock
IREE_DIR=${CACHE_DIR}/iree
VENV_DIR=${CACHE_DIR}/venv

# Version pins
IREE_GIT_TAG=3.7.0rc20250818
THEROCK_GIT_TAG=7.0.0rc20250818
THEROCK_DIST=therock-dist-linux-gfx94X-dcgpu
THEROCK_TAR=${THEROCK_DIST}-${THEROCK_GIT_TAG}.tar.gz

if [ ! -f "${CACHE_DIR}/.install_complete" ]; then
    echo "entrypoint.sh: Cache NOT found at ${CACHE_DIR}, proceeding with installation..."
    rm -rf ${CACHE_DIR}/*
    mkdir -p ${CACHE_DIR}

    # Install TheRock (ROCm/HIP) for GFX942
    echo "entrypoint.sh: Downloading TheRock (ROCm/HIP) prebuilt distribution for GFX942..."
    mkdir -p ${THEROCK_DIR}
    aria2c -x 16 -s 16 -d ${THEROCK_DIR} -o ${THEROCK_TAR} \
        https://therock-nightly-tarball.s3.us-east-2.amazonaws.com/${THEROCK_TAR}
    echo "entrypoint.sh: Extracting TheRock (ROCm/HIP) prebuilt distribution for GFX942..."
    tar -xf ${THEROCK_DIR}/${THEROCK_TAR} -C ${THEROCK_DIR}
    rm -f ${THEROCK_DIR}/${THEROCK_TAR}
    export PATH="${THEROCK_DIR}/bin:${PATH}"
    export LD_LIBRARY_PATH="${THEROCK_DIR}/lib"

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
    # Setting PATH to ${VENV_DIR}/bin is equivalent to activating the venv
    # https://pythonspeed.com/articles/activate-virtualenv-dockerfile/
    export PATH="${VENV_DIR}/bin:${PATH}"
    pip install \
        filecheck \
        lit \
        --find-links https://iree.dev/pip-release-links.html \
        iree-base-compiler==${IREE_GIT_TAG}

    # Used to validate cache for future runs
    touch "${CACHE_DIR}/.install_complete"

else
    echo "entrypoint.sh: Cache found at ${CACHE_DIR}, skipped installation..."
    export PATH="${VENV_DIR}/bin:${THEROCK_DIR}/bin:${PATH}"
    export LD_LIBRARY_PATH="${THEROCK_DIR}/lib"
fi

# Execute the command passed to the container
exec "$@"
