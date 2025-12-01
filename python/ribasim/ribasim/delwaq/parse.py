"""Read a Delwaq model generated from a Ribasim model and inject the results back to Ribasim."""

from pathlib import Path

import ribasim
from ribasim.utils import MissingOptionalModule, _concat

try:
    import xugrid as xu
except ImportError:
    xu = MissingOptionalModule("xugrid", "delwaq")


def parse(
    model: Path | ribasim.Model, graph, substances, output_folder=None
) -> ribasim.Model:
    if not isinstance(model, ribasim.Model):
        model = ribasim.Model.read(model)
    else:
        model = model.copy(deep=True)

    # Output of Delwaq
    if output_folder is None:
        assert model.filepath is not None
        output_folder = model.filepath.parent / "delwaq"
    with xu.open_dataset(output_folder / "delwaq_map.nc") as ug:
        mapping = dict(graph.nodes(data="id"))
        # Continuity is a (default) tracer representing the mass balance
        substances.add("Continuity")

        dfs = []
        for substance in substances:
            df = (
                ug[f"ribasim_{substance.replace(' ', '_')}"]
                .to_dataframe()
                .reset_index()
            )
            df.rename(
                columns={
                    "ribasim_nNodes": "node_id",
                    "nTimesDlwq": "time",
                    f"ribasim_{substance.replace(' ', '_')}": "concentration",
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

    df = _concat(dfs).reset_index(drop=True)
    df.sort_values(["time", "node_id"], inplace=True)

    model.basin.concentration_external = df
    df.to_feather(model.results_path / "basin_concentration_external.arrow")

    return model
