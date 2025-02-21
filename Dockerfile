ARG BASE_IMG=ubuntu:22.04
FROM ${BASE_IMG} AS dev-base

# Specify user IDs
ARG GROUP
ARG GID
ARG USER
ARG UID

# Run below commands as root
USER root

# Install basic packages
RUN apt-get update && \
    apt-get install -y \
    wget \
    lld \
    clang \
    clang-format \
    gdb \
    black \
    git \
    python3-dev \
    python3-venv \
    vim \
    ccache \
    pre-commit \
    sudo

# Install bazel
ARG ARCH="x86_64"
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel \
    && chmod a+x /usr/bin/bazel

# Clean up
RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Set workdir before launching container
WORKDIR /src

# Add user permissions
RUN groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    chown -R ${USER}:${GROUP} /src && \
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Switch to user
USER ${USER}
