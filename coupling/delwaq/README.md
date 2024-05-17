# Ribasim Delwaq coupling


## Steps
Choose a model and run it. For example, running the basic model with the Ribasim CLI:
```bash
ribasim generated_testmodels/basic/ribasim.toml
```

Run `generate.py` to generate a Delwaq model. Open a terminal in the Ribasim repository root and run:
```bash
python ./coupling/delwaq/generate.py
```
The script can:
- Open an existing Ribasim model (hardcoded to `generated_testmodels/basic/ribasim.toml` for now)
- Convert the metadata, topology and substances to Delwaq format and put it into the `model` folder

You now should manually run Delwaq. If you're an Deltares employee, you can do so with the Docker image.
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

If everything worked out, there's now a new netCDF output. We'll use this to update the Ribasim model.
Run `parse.py` again to update the Ribasim model with the new concentrations.

## Notes
I've tested this with a basic model, and the latest ribasim-nl (hws) model.
In the latter I've set a (static) concentration on the Rijn and Maas FlowBoundaries, which will create individual tracers for these nodes (named FlowBoundary_#node_id). For the LevelBoundaries, I've set a concentration of 34 for all North Sea nodes, assuming Cl as substance.
