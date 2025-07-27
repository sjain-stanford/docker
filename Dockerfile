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
ARG WORKDIR

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

# Install python venv and pip deps
# Setting VIRTUAL_ENV and PATH are equivalent to activating the venv
# https://pythonspeed.com/articles/activate-virtualenv-dockerfile/
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN python3 -m venv ${VIRTUAL_ENV}
RUN pip install \
    lit

# Set workdir before launching container
WORKDIR ${WORKDIR}

# Mirror user and group within container
# and set ownerships
RUN groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    chown -R ${USER}:${GROUP} ${WORKDIR} && \
    chown -R ${USER}:${GROUP} /opt/venv

# Switch to user
USER ${USER}
