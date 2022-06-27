# %%

import imod
import numpy as np
import pandas as pd
import xarray as xr

# %%

weir_area_path = r"../data/coupling/tmp/vlvalue.dik"
weir_area = pd.read_csv(
    weir_area_path,
    delim_whitespace=True,
    names=["lsw", "weir_area", "volume", "level", "slope"],
)
# %%
nsections_volume = weir_area.groupby(["lsw", "weir_area"])["volume"].count()
nsections_level = weir_area.groupby(["lsw", "weir_area"])["level"].count()
assert (nsections_volume == nsections_level).all()
nsections_max = nsections_volume.max()

# %%

stage_correction = pd.read_csv("mozart-coupling-data/MFtoLSW.csv")
dis = xr.open_dataset("netcdf/dis.nc")
template = dis["top"]

# %%

ds = xr.Dataset()

i = stage_correction["row"].values - 1
j = stage_correction["col"].values - 1
ds["correction"] = xr.full_like(template, np.nan)
ds["correction"].values[i, j] = stage_correction["oppw.correctie"].values

ds["lsw_id"] = xr.full_like(template, np.nan)
ds["lsw_id"].values[i, j] = stage_correction["LSWNUM"].values

ds["weir_area"] = xr.full_like(template, np.nan)
ds["weir_area"].values[i, j] = stage_correction["PV"].values

# %%

ds.to_netcdf("modflow-mozart-coupling.nc")

# %%


import xarray as xr

ds = xr.open_dataset(r"c:\projects\NHI-prototype\modflow\netcdf\modflow-mozart-coupling.nc")
# %%

import numpy as np

lsw_ids = np.unique(ds["lsw_id"])
lsw_ids = lsw_ids[~np.isnan(lsw_ids)]


# %%

dik_lsw = weir_area["lsw"].unique()

# %%