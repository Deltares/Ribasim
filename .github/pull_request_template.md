Fixes #

# Description




---
text below is for instruction and can be removed

# New node types
Typically new node types require an update of:

- `core/src/create.jl`
- `core/src/validation.jl`
- `core/src/solve.jl`

Updating other julia files may be required.


## ribasim_python
- `new_node_type.py` with associated implementation in `python/ribasim/ribasim`.
- add/update nodetype to `python/ribasim/ribasim/model.py`
- add/update nodetype to `python/ribasim/tests/conftest.py`
- add/update nodetype to `python/ribasim_api/tests/conftest.py`

## documentation

- update `docs/core/equations.qmd`
- update `docs/core/usage.qmd`
- update `docs/python/examples.ipynb`  # or start a new example model
- update `docs/schema*.json` by running `pixi run codegen`
- update the instructions in `docs/contribute/*.qmd` if something changes there, e.g. something changes in how a new node type must be defined.

## QGIS
- update `qgis/core/nodes.py`
