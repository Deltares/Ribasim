# Ribasim Delwaq coupling


## Steps
Choose a testmodel and run it. For example:
```bash
./build/ribasim_cli/bin/ribasim generated_testmodels/basic/ribasim.toml`
```

Run `gen_delwaq.py` to couple the models. The script can:
- Open an existing Ribasim model (hardcoded to `generated_testmodels/basic/ribasim.toml` for now)
- Convert the metadata, topology and substances to Delwaq format and put it into the `model` folder

You now should manually run Delwaq. You can do so with the Docker image. To do so, follow
this guide https://publicwiki.deltares.nl/display/Delft3DContainers/. Notably, you need
to login to https://containers.deltares.nl and create a token which you can use in the following steps.

```bash
docker login containers.deltares.nl  # use your deltares email + token
```

You can now run the Delwaq model from this directory.
```bash
docker run --mount type=bind,source="$(pwd)/model",target=/mnt/myModel \
  --workdir /mnt/myModel containers.deltares.nl/delft3d/delft3dfm run_dimr.sh
```

If everything worked out, there's now a new netcdf output. We'll use this to update the Ribasim model.
Run `parse_delwaq.py` again to update the Ribasim model with the new concentrations.

## Notes
I've tested this with a basic model, and the latest ribasim-nl (hws) model.
In the latter I've set a (static) concentration on the Rijn and Maas FlowBoundaries, which will create individual tracers for these nodes (named FlowBoundary_#node_id). For the LevelBoundaries, I've set a concentration of 34 for all North Sea nodes, assuming Cl as substance.
