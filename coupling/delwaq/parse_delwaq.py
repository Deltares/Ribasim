"""Read a Delwaq model generated from a Ribasim model and inject it back to Ribasim."""

from pathlib import Path

import ribasim
import xarray as xr
import xugrid as xu

output_folder = Path("model")

# TODO Have a shared config...
modelfn = Path("../../generated_testmodels/basic/ribasim.toml")
modelfn = Path("../../nl/hws.toml")
model = ribasim.Model.read(modelfn)

ds = xr.open_dataset(output_folder / "delwaq_map.nc")
ug = xu.UgridDataset(ds)
ug["ribasim_network_Cl"].to_numpy()
