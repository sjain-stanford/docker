ARG BASE_IMG=ubuntu:24.04
FROM ${BASE_IMG} AS dev-base

# https://askubuntu.com/questions/1513927/ubuntu-24-04-docker-images-now-includes-user-ubuntu-with-uid-gid-1000
RUN userdel -r ubuntu || true

# Specify user IDs and recreate env in container
# These are passed in from the build_docker.sh script
# Defaults to root user when not specified
ARG GROUP=root
ARG GID=0
ARG USER=root
ARG UID=0
ARG WORKDIR=/workspace

# Run below commands as root
USER root

# Install basic packages
RUN apt-get update && \
    apt-get install -y \
    aria2 \
    bash-completion \
    black \
    sudo \
    catch2 \
    ccache \
    clang \
    clang-format \
    clang-tidy-19 \
    cmake-curses-gui \
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
    wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install bazel
ARG ARCH=x86_64
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel && \
    chmod a+x /usr/bin/bazel

# Set workdir before launching container
WORKDIR ${WORKDIR}

# Install IREE, ROCm, HIP deps through an entrypoint script
# to keep the base image small and portable.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY activate /usr/local/bin/activate
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]

# Mirror user and group within container and set ownerships
# only if building as non-root user (i.e., GROUP, GID, USER,
# UID and WORKDIR are specified args to docker build)
RUN if [ "$UID" != "0" ]; then \
    groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} && \
    chown -R ${USER}:${GROUP} ${WORKDIR}; \
    fi

# Switch to user
USER ${USER}
