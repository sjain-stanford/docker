ARG BASE_IMG=ubuntu:24.04
FROM ${BASE_IMG} AS dev-base

# https://askubuntu.com/questions/1513927/ubuntu-24-04-docker-images-now-includes-user-ubuntu-with-uid-gid-1000
RUN userdel -r ubuntu

# Specify user IDs and recreate env in container
# These are passed in from the run_docker.sh script
ARG GROUP
ARG GID
ARG RENDER_GID
ARG USER
ARG UID
ARG WORKDIR

# Run below commands as root
USER root

# What's needed to install a PPA
RUN apt-get update && \
    apt-get install -y ca-certificates gpg wget

# Kitware ppa for the latest CMake
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc \
    | gpg --dearmor | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ noble main' \
    | tee /etc/apt/sources.list.d/kitware.list >/dev/null

# ROCm PPA
RUN wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.4.3 noble main" \
    | tee /etc/apt/sources.list.d/rocm.list && \
    printf 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600\n' \
    > /etc/apt/preferences.d/rocm-pin-600

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
    rocm

# Install bazel
ARG ARCH="x86_64"
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel && \
    chmod a+x /usr/bin/bazel

# Clean up
RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Build IREE Runtime (from source)
#   HIP_API_HEADERS_ROOT   - use hip headers from rocm install rather than iree
#                            specific copy of said headers. Not necessary, but
#                            nice for development.
ARG IREE_GIT_TAG=3.7.0rc20250724
RUN git clone --depth=1 --branch iree-${IREE_GIT_TAG} https://github.com/iree-org/iree.git /opt/iree && \
    cd /opt/iree && \
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
        -DHIP_API_HEADERS_ROOT=/opt/rocm/include \
        -DIREE_ERROR_ON_MISSING_SUBMODULES=OFF \
        -DIREE_HAL_DRIVER_DEFAULTS=OFF \
        -DIREE_HAL_DRIVER_LOCAL_SYNC=ON \
        -DIREE_HAL_DRIVER_LOCAL_TASK=ON \
        -DIREE_HAL_DRIVER_HIP=ON && \
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

# Mirror user and group within container
# and set ownerships + password-less sudo for user.
RUN groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} && \
    chown -R ${USER}:${GROUP} ${WORKDIR} && \
    chown -R ${USER}:${GROUP} /opt

# Create and add user to "render" + "video" groups. ROCm requires accesses to the
# host’s /dev/kfd and /dev/dri/* device nodes owned by the "render" and "video"
# groups. The groups’ GIDs in the container must match the host’s to access the
# resources. In ubuntu 24.4 the "video" group always exists, with GID 44, so we
# only need to create "render" group.
RUN if [ -n "$RENDER_GID" ]; then groupadd -g "$RENDER_GID" render; fi && \
    usermod -aG render,video ${USER}

# Switch to user
USER ${USER}
