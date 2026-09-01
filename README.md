# Interactive docker for ML compiler development

Simply clone this repo:
```
git clone https://github.com/sjain-stanford/docker.git
```

### Interactive development

Switch over to the development repo and launch an interactive container:
```
/path/to/docker/run_docker.sh
```

This launches an interactive shell within the container. All code in the current directory should be visible (volume mounted) within the container at the same paths, preserving the source structure to keep builds within container in sync with utilities outside (e.g. `compile_commands.json`, C++ Intellisense, gcov-viewer etc.). The container also mounts user's home directory so that their configuration works as-is within the container (e.g. `.bashrc`, `.gitconfig` etc). The container automatically sources its virtual environment in the interactive shell, which should reflect in `$PATH` and `$LD_LIBRARY_PATH` appropriately. This may be manually disabled with `deactivate` and re-enabled with `source activate`.

To use VSCode's integrated debugger with the container, we recommend using the "Dev Containers" extension. Simply `run_docker.sh` to launch the container, then press Ctrl+Shift+P (or Cmd+Shift+P on macOS) to open the command palette and select "Dev Containers: Attach to Running Container...". See [this](https://code.visualstudio.com/docs/devcontainers/attach-container) for details.

### Peanut-review web UI over Remote SSH

VSCode Remote SSH discovers ports on the SSH host, while services started in a
Docker container normally listen in a separate network namespace. Opt in to a
loopback-only port publication when launching the development container:

```bash
DOCKER_ENABLE_PEANUT_REVIEW_WEB=1 /path/to/docker/run_docker.sh
```

Then start peanut-review inside the container with its web UI launcher. The
launcher detects Docker and binds the container interface rather than
container-local loopback:

```bash
PR_ROOT=~/claude-workspace/.cache/peanut-review/sessions \
PR_PORT="$PEANUT_REVIEW_PORT" \
  tools/peanut-review/bin/peanut_review_serve.sh
```

The default port is `27183`. VSCode can auto-forward that remote-host port, or
it can be forwarded from the **Ports** view. Open
`http://localhost:27183/` on the local laptop. `PR_ROOT` must match the
`reviewRoot` used when creating the peanut-review sessions.

Do not set `PR_BASE_URL` or pass `--base-url` for direct port forwarding. That
option only rewrites generated links when a reverse proxy mounts peanut-review
under a path prefix and strips the prefix before forwarding requests to the
server.

Set `PEANUT_REVIEW_PORT` before launching the container to use another port:

```bash
DOCKER_ENABLE_PEANUT_REVIEW_WEB=1 PEANUT_REVIEW_PORT=37183 \
  /path/to/docker/run_docker.sh
```

The published host socket is deliberately bound to `127.0.0.1`; the web UI is
not exposed on the SSH host's external network interfaces. A Dockerfile
`EXPOSE` instruction is neither needed nor sufficient for this forwarding.

### Non-interactive usage (CI)

To execute commands within the container in batch mode (non-interactive):
```
/path/to/docker/exec_docker.sh <command>
```

For example:
```
/path/to/docker/exec_docker.sh echo "Hello World"

/path/to/docker/exec_docker.sh bash -c "echo "Hello" && echo "World""
```

### Bubblewrap sandbox support

The image installs `bubblewrap` and keeps `/usr/bin/bwrap` in setuid mode so
non-root users inside the container can create nested user/mount namespaces.
The local launcher scripts (`run_docker.sh` and `exec_docker.sh`) also pass the
Docker runtime options needed for Codex's Linux sandbox:

```
--cap-add=SYS_ADMIN
--cap-add=SYS_CHROOT
--cap-add=NET_ADMIN
--cap-add=NET_RAW
--cap-add=SETUID
--cap-add=SETGID
--cap-add=SYS_PTRACE
--security-opt=seccomp=unconfined
--security-opt=apparmor=unconfined
```

These options follow the [secure OpenAI Codex devcontainer profile](https://github.com/openai/codex/tree/main/.devcontainer)'s
bwrap sandbox requirements. They are enabled by default for local launchers and
can be disabled with:

```
DOCKER_ENABLE_BWRAP_SANDBOX=0 /path/to/docker/run_docker.sh
```

### Host Docker access

The image includes the Docker CLI. Host Docker access is disabled by default
because mounting `/var/run/docker.sock` grants broad control over the host
daemon. When explicitly enabled on hosts that have `/var/run/docker.sock`,
`run_docker.sh` and `exec_docker.sh` mount that socket into the dev container,
add the socket-owning group ID so the non-root container user can talk to the
host Docker daemon, and pass `DOCKER_API_VERSION` so the container Docker CLI
can talk to older host daemons. Containers launched from inside the dev container
are host-level sibling containers, not nested containers inside the dev
container.

Enable host Docker access with:

```
DOCKER_ENABLE_HOST_DOCKER=1 /path/to/docker/run_docker.sh
```

Once inside the dev container:

```
docker ps
docker run --rm hello-world
```

Bind mounts passed to inner `docker run` commands are resolved by the host Docker
daemon. Prefer mounting paths that already exist at the same absolute path on the
host and in the dev container, for example:

```
docker run --rm -it -v "$PWD:$PWD" -w "$PWD" ubuntu:26.04 bash
```

Mounting the host Docker socket grants broad control over the host daemon, so only
use this with trusted dev containers and workloads.

### Host AMD GPU access

The launch scripts expose the host AMD GPUs by default by passing `/dev/kfd` and
the `/dev/dri/*` character devices to Docker. Disable those mappings when a
workload should see only simulated GPUs, such as when testing rocjitsu:

```
DOCKER_ENABLE_AMD_GPU=0 AMD_ARCH=gfx950 /path/to/docker/run_docker.sh
```

This removes access to the physical GPUs without removing the ROCm compiler,
HIP runtime, HSA runtime, or other userspace libraries from the container. Set
`AMD_ARCH` explicitly to select the TheRock distribution used to compile and
run the simulated target.

Inside the container, verify that the physical GPU device nodes are absent:

```
test ! -e /dev/kfd
test ! -e /dev/dri
```

The option also applies to `exec_docker.sh` and `exec_docker_ci.sh`. The default
is `DOCKER_ENABLE_AMD_GPU=1` for backward compatibility.

### GPU architecture selection

The launch scripts pass `AMD_ARCH` into the container so `entrypoint.sh` can
download the matching TheRock distribution. If `AMD_ARCH` is unset, the scripts
try to detect the first host GPU reported by `rocminfo`.

Override detection when needed:

```
AMD_ARCH=gfx950 /path/to/docker/run_docker.sh
```

Supported values are `gfx94X`/`gfx942`, `gfx950`, `gfx110X`/`gfx1100`-`gfx1103`,
and `gfx120X`/`gfx1200`/`gfx1201`. If no ROCm GPU is detected and
`AMD_ARCH` is not set, the container falls back to `gfx94X`.

> [!NOTE]
> To keep the docker image size small (<2GB), the installation of large libraries (e.g. ROCm) is deferred to container launch through an `entrypoint.sh`. This installation is cached locally at `${PWD}/.cache/docker` so re-runs are instantaneous. The cache is automatically invalidated when the TheRock version or selected distribution changes. To force a clean reinstall, remove the `${PWD}/.cache/docker` directory and re-run.

Happy development!

### Tested Projects

- https://github.com/iree-org/fusilli
- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
