# Interactive docker for compiler development

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

Happy development!


### Tested Projects

- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
- https://github.com/nod-ai/shark-ai/tree/main/sharkfuser
