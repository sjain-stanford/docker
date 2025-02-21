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

All projects in the parent directory should now be visible (volume mounted) within the container.


### Tested Projects

- https://github.com/llvm/torch-mlir
- https://github.com/llvm/mlir-tcp
