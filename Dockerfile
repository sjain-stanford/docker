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
    bubblewrap \
    ca-certificates \
    sudo \
    catch2 \
    ccache \
    clang \
    clang-format \
    clang-tidy \
    cmake-curses-gui \
    cmake \
    curl \
    gdb \
    git \
    git-lfs \
    gnupg \
    lcov \
    lld \
    ninja-build \
    pre-commit \
    python3-dev \
    python3-venv \
    ripgrep \
    vim \
    wget && \
    git lfs install --system && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup GitHub CLI repository and install gh
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -nv -O /tmp/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
    cat /tmp/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/githubcli-archive-keyring.gpg

# Install Node.js and Codex CLI
# https://help.openai.com/en/articles/11096431-openai-codex-ci-getting-started
ARG NODE_MAJOR=22
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -nv -O /tmp/nodesource-repo.gpg.key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key && \
    gpg --batch --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource-repo.gpg.key && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list > /dev/null && \
    apt-get update && \
    apt-get install -y nodejs && \
    npm install -g @openai/codex && \
    npm cache clean --force && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/nodesource-repo.gpg.key

# Install bazel
ARG ARCH=x86_64
ARG BAZEL_VERSION=6.4.0
RUN wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-${ARCH} -O /usr/bin/bazel && \
    chmod a+x /usr/bin/bazel

# Install beads_rust (br) - agent-first issue tracker
RUN curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh" | bash -s -- --system

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
#
# NOTE: When WORKDIR lies under /home/${USER} the WORKDIR instruction above
# already created the home as root -- useradd -m skips chown on a pre-existing
# home. We chown /home/${USER} as well as ${WORKDIR} to ensure that the user
# owns /home/${USER}.
RUN if [ "$UID" != "0" ]; then \
    groupadd -o -g ${GID} ${GROUP} && \
    useradd -u ${UID} -g ${GROUP} -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/bin/tee, /usr/bin/chown, /usr/bin/chmod" > /etc/sudoers.d/${USER} && \
    chown -R ${USER}:${GROUP} ${WORKDIR} /home/${USER}; \
    fi

# Strip setuid/setgid bits, then restore bubblewrap's setuid helper so
# non-root users can create Codex's inner Linux sandbox inside Docker.
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true && \
    chmod u+s /usr/bin/bwrap

# Switch to user
USER ${USER}
