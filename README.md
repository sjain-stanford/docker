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
docker run --rm -it -v "$PWD:$PWD" -w "$PWD" ubuntu:24.04 bash
```

Mounting the host Docker socket grants broad control over the host daemon, so only
use this with trusted dev containers and workloads.

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

> [!NOTE]
> To keep the docker image size small (<2GB), the installation of large libraries (e.g. ROCm/IREE) is deferred to container launch through an `entrypoint.sh`. This installation is cached locally at `${PWD}/.cache/docker` so re-runs are instantaneous. The cache is automatically invalidated when IREE or TheRock versions change. To force a clean reinstall, remove the `${PWD}/.cache/docker` directory and re-run.

Happy development!

### Tested Projects

- https://github.com/iree-org/fusilli
- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
