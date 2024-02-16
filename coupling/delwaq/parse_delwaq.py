"""Read a Delwaq model generated from a Ribasim model and inject it back to Ribasim."""

from pathlib import Path

import ribasim
import xarray as xr
import xugrid as xu

output_folder = Path("model")

modelfn = Path("../../generated_testmodels/basic/ribasim.toml")
model = ribasim.Model.read(modelfn)

ds = xr.open_dataset(output_folder / "Delwaq/delwaq_map.nc")
ug = xu.UgridDataset(ds)
ug["network1d_Continuity"].plot(clim=(0, 2))
