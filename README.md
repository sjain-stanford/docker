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

> [!WARNING]
> To keep the docker image size small (<2GB), the installation of large libraries (e.g. ROCm/IREE) is deferred to container launch through an `entrypoint.sh`. This installation is cached locally at `${PWD}/.cache/docker` so re-runs are instantaneous. However, the cache is NOT automatically invalidated and needs to be cleared manually (like when library versions are bumped). To clear the installation cache, simply remove the `${PWD}/.cache/docker` directory and re-run.

Happy development!

### Tested Projects

- https://github.com/iree-org/fusilli
- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
