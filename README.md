# Interactive docker for compiler development

Simply clone this repo (alongside other repos):
```
git clone https://github.com/sjain-stanford/docker.git
```

Switch over to the parent directory and launch an interactive container:
```
cd ../
./docker/run_docker.sh
```

All code in the parent directory should be visible (volume mounted) within the container at the same paths, preserving the source structure to keep builds within container in sync with utilities outside (e.g. compile_commands.json, Intellisense, gcov-viewer etc.). The container also mounts user's home directory so that their 
configuration works as-is within the container (e.g. .bashrc, .gitconfig etc). Even
the python virtual environment is setup to persist between container attach/detach sessions.

Happy development!


### Tested Projects

- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
- https://github.com/nod-ai/shark-ai/tree/main/sharkfuser
