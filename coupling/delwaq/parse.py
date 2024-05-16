"""Read a Delwaq model generated from a Ribasim model and inject it back to Ribasim."""

from pathlib import Path

import geopandas as gpd
import ribasim
import xarray as xr
import xugrid as xu

delwaq_dir = Path(__file__).parent
repo_dir = delwaq_dir.parents[1]
output_folder = delwaq_dir / "model"

# TODO Have a shared config...
modelfn = repo_dir / "generated_testmodels/basic/ribasim.toml"
# modelfn = repo_dir / "models/hws_2024_3_0/hws.toml"
model = ribasim.Model.read(modelfn)

# Output of Delwaq
ds = xr.open_dataset(output_folder / "delwaq_map.nc")
ug = xu.UgridDataset(ds)

# Generated for Delwaq, contains the original node ids
rds = xr.open_dataset(output_folder / "ribasim.nc")
rug = xu.UgridDataset(rds)

# Chloride concentration
df = (
    ug["ribasim_network_Cl"].to_dataframe().reset_index()
    # .drop(columns=["ribasim_network_node_x", "ribasim_network_node_y"])
)
df.rename(
    columns={
        "nTimesDlwq": "datetime",
        "ribasim_network_nNodes": "node_id",
        "ribasim_network_Cl": "concentration",
        "ribasim_network_node_x": "x",
        "ribasim_network_node_y": "y",
    },
    inplace=True,
)
# Map the node_id (logical index) to the original node_id
df["node_id"] = rug["node_id"].to_numpy()[df.node_id.to_numpy()]

# Only keep the basin nodes
mask = df["node_id"].isin(model.basin.node_ids())
df = df[mask]
gdf = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df.x, df.y), crs=28992)
gdfs = gdf.iloc[:100_000]
gdfs.to_file("delwaq.gpkg", layer="Cl", driver="GPKG")

# TODO: Handle existing timeseries instead of overwriting
model.basin.time = df
model.write(modelfn)
