ARG BASE_IMG=ubuntu:24.04
FROM ${BASE_IMG} AS dev-base

# https://askubuntu.com/questions/1513927/ubuntu-24-04-docker-images-now-includes-user-ubuntu-with-uid-gid-1000
RUN userdel -r ubuntu

# Specify user IDs and recreate env in container
# These are passed in from the run_docker.sh script
ARG GROUP
ARG GID
ARG USER
ARG UID
ARG PWD

# Run below commands as root
USER root

# Install basic packages
RUN apt-get update && \
    apt-get install -y \
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
    stow \
    vim \
    wget

# Install bazel
ARG ARCH="x86_64"
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel \
    && chmod a+x /usr/bin/bazel

# Install iree
RUN wget -q https://github.com/iree-org/iree/releases/download/v3.6.0/iree-dist-3.6.0rc20250718-linux-x86_64.tar.xz -O /tmp/iree-dist.tar.xz \
    && mkdir -p /usr/local/stow/iree-dist \
    && tar -xf /tmp/iree-dist.tar.xz -C /usr/local/stow/iree-dist \
    && rm /tmp/iree-dist.tar.xz \
    && stow -d /usr/local/stow -t /usr/local iree-dist

# Clean up
RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Set workdir before launching container
WORKDIR ${PWD}

# Install python pip deps through an entrypoint script
COPY ./docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]

# Add user permissions
RUN groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    chown -R ${USER}:${GROUP} ${PWD}

# Switch to user
USER ${USER}
