ARG BASE_IMG=ubuntu:24.04
FROM ${BASE_IMG} AS dev-base

# https://askubuntu.com/questions/1513927/ubuntu-24-04-docker-images-now-includes-user-ubuntu-with-uid-gid-1000
RUN userdel -r ubuntu

# Specify user IDs and recreate env in container
# These are passed in from the build_docker.sh script
ARG GROUP
ARG GID
ARG USER
ARG UID
ARG WORKDIR
# Group IDs for `render` and `video` groups (needed for exposing GPU devices on host)
ARG RENDER_GID
ARG VIDEO_GID

# Run below commands as root
USER root

# Install basic packages
RUN apt-get update && \
    apt-get install -y \
    bash-completion \
    black \
    catch2 \
    ccache \
    clang \
    clang-format \
    cmake \
    gdb \
    git \
    lcov \
    lld \
    ninja-build \
    pre-commit \
    python3-dev \
    python3-venv \
    vim \
    wget

# Install bazel
ARG ARCH=x86_64
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel && \
    chmod a+x /usr/bin/bazel

# Clean up
RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install HIP/ROCm for GFX942 (from TheRock prebuilt dist)
ARG THEROCK_DIST=gfx94X-dcgpu-7.0.0rc20250818
ENV THEROCK_DIR=/opt/therock-build
ENV PATH="${THEROCK_DIR}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${THEROCK_DIR}/lib:${LD_LIBRARY_PATH}"
RUN mkdir ${THEROCK_DIR} && \
    wget -q https://therock-nightly-tarball.s3.us-east-2.amazonaws.com/therock-dist-linux-${THEROCK_DIST}.tar.gz -O ${THEROCK_DIR}/therock-dist-linux-${THEROCK_DIST}.tar.gz && \
    cd ${THEROCK_DIR} && \
    tar -xf *.tar.gz && \
    rm -f *.tar.gz

# Build IREE Runtime (from source)
ARG IREE_GIT_TAG=3.7.0rc20250818
ENV IREE_DIR=/opt/iree
RUN git clone --depth=1 --branch iree-${IREE_GIT_TAG} https://github.com/iree-org/iree.git ${IREE_DIR} && \
    cd ${IREE_DIR} && \
    git submodule update --init \
        third_party/hip-build-deps \
        third_party/cpuinfo \
        third_party/benchmark \
        third_party/flatcc && \
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
        -DHIP_API_HEADERS_ROOT=${THEROCK_DIR}/include && \
    cmake --build build --target all

# Install python venv and pip deps
# Setting VIRTUAL_ENV and PATH are equivalent to activating the venv
# https://pythonspeed.com/articles/activate-virtualenv-dockerfile/
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN python3 -m venv ${VIRTUAL_ENV}
RUN pip install \
    filecheck \
    lit \
    --find-links https://iree.dev/pip-release-links.html \
    iree-base-compiler==${IREE_GIT_TAG}

# Set workdir before launching container
WORKDIR ${WORKDIR}

# Mirror user and group within container and set ownerships
RUN groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    chown -R ${USER}:${GROUP} ${WORKDIR} && \
    chown -R ${USER}:${GROUP} /opt

# Create `render` & `video` groups (unless they already exist) and add user to it.
# ROCm requires accesses to the host’s /dev/kfd and /dev/dri/* device nodes owned
# by the `render` and `video` groups. The groups’ GIDs in the container must match
# the host’s to access the resources. The `-f` exit successfully if the group
# already exists, and cancels -g if the GID is already used.
RUN if [ -n "$RENDER_GID" ]; then groupadd -f -g "$RENDER_GID" render; else groupadd -f render; fi && \
    if [ -n "$VIDEO_GID" ]; then groupadd -f -g "$VIDEO_GID" video; else groupadd -f video; fi && \
    usermod -aG render,video ${USER}

# Switch to user
USER ${USER}
