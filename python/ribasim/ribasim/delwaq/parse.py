"""Read a Delwaq model generated from a Ribasim model and inject the results back to Ribasim."""

from pathlib import Path

import pandas as pd

import ribasim
from ribasim.utils import MissingOptionalModule

try:
    import xugrid as xu
except ImportError:
    xu = MissingOptionalModule("xugrid", "delwaq")

delwaq_dir = Path(__file__).parent
repo_dir = delwaq_dir.parents[1]
output_folder = delwaq_dir / "model"


def parse(toml_path: Path, graph, substances) -> ribasim.Model:
    model = ribasim.Model.read(toml_path)

    # Output of Delwaq
    ug = xu.open_dataset(output_folder / "delwaq_map.nc")

    mapping = dict(graph.nodes(data="id"))
    # Continuity is a (default) tracer representing the mass balance
    substances.add("Continuity")

    dfs = []
    for substance in substances:
        df = ug[f"ribasim_{substance}"].to_dataframe().reset_index()
        df.rename(
            columns={
                "ribasim_nNodes": "node_id",
                "nTimesDlwq": "time",
                f"ribasim_{substance}": "concentration",
            },
            inplace=True,
        )
        df["substance"] = substance
        df.drop(columns=["ribasim_node_x", "ribasim_node_y"], inplace=True)
        # Map the node_id (logical index) to the original node_id
        # TODO Check if this is correct
        df.node_id += 1
        df.node_id = df.node_id.map(mapping)

        dfs.append(df)

    df = pd.concat(dfs).reset_index(drop=True)
    df.sort_values(["time", "node_id"], inplace=True)

    model.basin.concentration_external = df
    df.to_feather(toml_path.parent / "results" / "basin_concentration_external.arrow")

    return model
