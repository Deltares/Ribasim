"""Read a Delwaq model generated from a Ribasim model and inject the results back to Ribasim."""

import argparse
import logging
from pathlib import Path

import xarray as xr

import ribasim
from ribasim.utils import _concat


def parse(
    model: Path | ribasim.Model,
    output_folder: str | Path | None = None,
    *args,
    to_input: bool = False,
) -> ribasim.Model:
    # parse() used to take (model, graph, substances, output_folder); the graph
    # mapping and substances are now read from the ribasim.nc file written by
    # generate(), so those arguments are no longer needed.
    if args or not isinstance(output_folder, (str, Path, type(None))):
        raise TypeError(
            "parse() no longer takes `graph` and `substances` arguments; they are "
            "read from the `ribasim.nc` file written by generate(). "
            "Call parse(model, output_folder=..., to_input=...) instead."
        )

    if not isinstance(model, ribasim.Model):
        model = ribasim.Model.read(model)
    else:
        model = model.model_copy(deep=True)

    # Output of Delwaq
    if isinstance(output_folder, (str, Path)):
        folder = Path(output_folder)
    else:
        assert model.filepath is not None
        folder = model.filepath.parent / "delwaq"

    # Recover the node mapping (Delwaq segment -> original Ribasim node_id) and
    # the substances from the mesh file written by generate().
    with xr.open_dataset(folder / "ribasim.nc") as nc:
        mapping = dict(
            zip(
                nc["node_id"].to_numpy(),
                nc["ribasim_node_id"].to_numpy(),
                strict=True,
            )
        )
        substances = set(nc["substances"].to_numpy().astype(str))

    with xr.open_dataset(folder / "delwaq_map.nc") as ds:
        # Continuity is a (default) tracer representing the mass balance
        substances.add("Continuity")

        dfs = []
        for substance in substances:
            df = (
                ds[f"ribasim_{substance[:20].replace(' ', '_')}"]
                .to_dataframe()
                .reset_index()
            )
            df.rename(
                columns={
                    "ribasim_nNodes": "node_id",
                    "nTimesDlwq": "time",
                    f"ribasim_{substance[:20].replace(' ', '_')}": "concentration",
                },
                inplace=True,
            )
            df["substance"] = substance
            df.drop(columns=["ribasim_node_x", "ribasim_node_y"], inplace=True)
            # Map the node_id (logical index) to the original node_id
            # TODO Check if this is correct
            df["node_id"] += 1
            df["node_id"] = df["node_id"].map(mapping)

            dfs.append(df)

    df = _concat(dfs).reset_index(drop=True)
    df.sort_values(["time", "node_id"], inplace=True)

    ds = df.set_index(["time", "substance", "node_id"]).to_xarray()
    ds.to_netcdf(model.results_path / "concentration.nc")

    if to_input:
        # Optionally make the parsed results available as model input
        model.basin.concentration_external = df

    return model


if __name__ == "__main__":
    # Parse Delwaq output

    parser = argparse.ArgumentParser(description="Parse Delwaq output.")
    parser.add_argument(
        "toml_path", type=Path, help="The path to the Ribasim TOML file."
    )
    parser.add_argument(
        "--output_path",
        type=Path,
        help="The relative path to the Delwaq output.",
        default="delwaq",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Increase verbosity (-v for info, -vv for debug).",
    )
    args = parser.parse_args()

    log_level = logging.WARNING
    if args.verbose >= 2:
        log_level = logging.DEBUG
    elif args.verbose >= 1:
        log_level = logging.INFO
    logging.basicConfig(level=log_level)

    parse(args.toml_path, args.toml_path.parent / args.output_path)
