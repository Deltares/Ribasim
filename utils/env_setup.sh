#!/bin/bash
JULIAUP_DEPOT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export JULIAUP_DEPOT_PATH
QUARTO_PYTHON=python
export QUARTO_PYTHON
relative_conda_prefix=$(realpath --relative-to="$PWD" "$CONDA_PREFIX")
MYPYPATH=$relative_conda_prefix/share/qgis/python
export MYPYPATH
