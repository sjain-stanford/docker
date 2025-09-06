# Interactive docker for ML compiler development

Simply clone this repo:
```
git clone https://github.com/sjain-stanford/docker.git
```

Switch over to the development repo and launch an interactive container:
```
/path/to/docker/run_docker.sh
```

This launches an interactive shell within the container. All code in the current directory should be visible (volume mounted) within the container at the same paths, preserving the source structure to keep builds within container in sync with utilities outside (e.g. `compile_commands.json`, C++ Intellisense, gcov-viewer etc.). The container also mounts user's home directory so that their configuration works as-is within the container (e.g. `.bashrc`, `.gitconfig` etc).

To execute commands within the container non-interactively:
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

- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
- https://github.com/nod-ai/shark-ai/tree/main/sharkfuser
