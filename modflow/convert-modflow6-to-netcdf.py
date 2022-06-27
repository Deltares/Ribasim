# %%

import imod

# %%
def load_model_into_memory(path):
    simulation = imod.mf6.Modflow6Simulation.open(path)
    gwf = simulation["gwf_1"]

    for key, pkg in gwf.items():
        print(key)
        if "time" in pkg.dataset:
            pkg.dataset = pkg.dataset.isel(time=0, drop=True)
        pkg.dataset.load()
        if "layer" in pkg.dataset:
            pkg.dataset = pkg.dataset.dropna("layer", how="all")

    return simulation


# %%

#path = r"c:\projects\tki\LHM-mf6\7_LHM42_L15_KHV_KVA_CONSISTENT\MFSIM.NAM"
path = r"c:\projects\NHI-prototype\modflow\vanGijs-LHM-mf6\7_LHM42_L15_KHV_KVA_CONSISTENT_MZ\MFSIM.NAM"
simulation = load_model_into_memory(path)


# %%

model = simulation["gwf_1"]
idomain = model["dis"]

# %%

for name, pkg in model.items():
    pkg.dataset["x"].attrs = {
        "long_name": "x coordinate of projection",
        "standard_name": "projection_x_coordinate",
        "axis": "X",
        "units": "m",
    }
    pkg.dataset["y"].attrs = {
        "long_name": "x coordinate of projection",
        "standard_name": "projection_y_coordinate",
        "axis": "Y",
        "units": "m",
    }
    pkg.dataset.to_netcdf(f"netcdf/{name}.nc")
    
# %%