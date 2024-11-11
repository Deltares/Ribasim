# Ribasim Delwaq coupling
This folder contains scripts to setup a Delwaq model from a Ribasim model, and to update the Ribasim model with the Delwaq output.

## Steps
Setup a Ribasim model with substances and concentrations and run it. For example, we can run the basic testmodel with some default concentrations using the Ribasim CLI:

```bash
ribasim generated_testmodels/basic/ribasim.toml
```

Afterwards we can use the Ribasim model and the generated output to setup a Delwaq model using Python from this folder.

```python
from pathlib import Path

from generate import generate
from parse import parse
from util import run_delwaq

toml_path = Path("generated_testmodels/basic/ribasim.toml")

graph, substances = generate(toml_path)
run_delwaq()
model = parse(toml_path, graph, substances)
```

The resulting Ribasim model will have an updated `model.basin.concentration_external` table with the Delwaq output.
We also store the same table in the `basin_concentration_external.arrow` file in the results folder, which can be
referred to using the Ribasim config file.

## Running Delwaq
If you have access to a DIMR release, you can find the Delwaq executables in the `bin` folder. You can run a model directly with the `run_dimr.bat` script, and providing the path to the generated `.inp` file to it. In `util.py` we provide a `run_delwaq` (as used above) that does this for you, if you set the `D3D_HOME` environment variable to the path of the unzipped DIMR release, using the generated `model/ribasim.inp` configuration file.

### Running Delwaq with Docker
Alternative to running Delwaq with a DIMR release, you can also run the Delwaq model in a Docker container if you are a Deltares employee.
First install WSL and install docker in WSL, then create a CLI secret and log into the Deltares containers. To install docker in WSL and create a CLI secret for the following steps, follow this guide https://publicwiki.deltares.nl/display/Delft3DContainers/.

Log into Deltares containers in docker:
```bash
docker login containers.deltares.nl  # use your deltares email + token
```

You can now run the Delwaq model from this directory.
```bash
docker run --mount type=bind,source="$(pwd)/model",target=/mnt/myModel \
  --workdir /mnt/myModel containers.deltares.nl/delft3d/delft3dfm run_dimr.sh
```
