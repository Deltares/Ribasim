# %%
import os

os.environ["USE_PYGEOS"] = "0"

import numpy as np
import pandas as pd
import xarray as xr

import ribasim

# %%

model = ribasim.Model.from_toml("basic/basic.toml")

# %%

time = pd.date_range(model.starttime, model.endtime)
day_of_year = time.day_of_year.values
seconds_per_day = 24 * 60 * 60
evaporation = (
    (-1.0 * np.cos(day_of_year / 365.0 * 2 * np.pi) + 1.0) * 0.0025 / seconds_per_day
)
rng = np.random.default_rng()
precipitation = (
    rng.lognormal(mean=-1.0, sigma=1.7, size=time.size) * 0.001 / seconds_per_day
)

# %%
# We'll use xarray to easily broadcast the values.

timeseries = (
    pd.DataFrame(
        data={
            "node_id": 1,
            "time": time,
            "drainage": 0.0,
            "potential_evaporation": evaporation,
            "infiltration": 0.0,
            "precipitation": precipitation,
            "urban_runoff": 0.0,
        }
    )
    .set_index("time")
    .to_xarray()
)

basin_ids = model.basin.static["node_id"].unique()
basin_nodes = xr.DataArray(
    np.ones(len(basin_ids)), coords={"node_id": basin_ids}, dims=["node_id"]
)
forcing = (timeseries * basin_nodes).to_dataframe().reset_index()

# %%

state = pd.DataFrame(
    data={
        "node_id": basin_ids,
        "storage": 1000.0,
        "concentration": 0.0,
    }
)

# %%

model.basin.forcing = forcing
model.basin.state = state

# %%

model.write("basic-transient")
# %%
# After running the model, read back the input:

df = pd.read_feather(r"c:\src\Ribasim\examples\basic-transient\basin.arrow")
output = df.set_index(["time", "node_id"]).to_xarray()
output["level"].plot(hue="node_id")
# %%
