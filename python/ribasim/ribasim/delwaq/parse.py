"""
Parse Delwaq results from `generate` and save the results back to Ribasim.

Can be used as a command line tool:

usage: parse.py [-h] [--output_path OUTPUT_PATH] [-v] toml_path

positional arguments:
  toml_path             The path to the Ribasim TOML file.

options:
  -h, --help            show this help message and exit
  --output_path OUTPUT_PATH
                        The relative path to the Delwaq output.
  -v, --verbose         Increase verbosity (-v for info, -vv for debug).
"""

import argparse
import logging
from collections.abc import Callable, Collection
from pathlib import Path
from typing import Any, Literal, cast

import netCDF4
import numpy as np
import pandas as pd
import xarray as xr

import ribasim
from ribasim.config import Results
from ribasim.utils import _concat

# The tracers of the core, in the order of its results
_CORE_TRACERS = (
    "Continuity",
    "Initial",
    "LevelBoundary",
    "FlowBoundary",
    "Drainage",
    "Precipitation",
    "SurfaceRunoff",
    "ResidenceTime",
)

# Number of values in a chunk, 1 MiB of float64, as in the core
_NC_CHUNK_LENGTH = 131072


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

    substances = _ordered_substances(model, substances | {"Continuity"})

    with xr.open_dataset(folder / "delwaq_map.nc") as ds:
        time = ds["nTimesDlwq"].to_numpy()
        # Delwaq numbers its segments from 1, in the order of the mesh
        segment = np.arange(1, ds.sizes["ribasim_nNodes"] + 1)
        node_id = np.array([mapping[i] for i in segment], dtype=np.int32)
        # Like the core, sort the Basins by node_id
        order = np.argsort(node_id, kind="stable")
        node_id = node_id[order]

        def concentration(substance: str) -> np.ndarray:
            """Return the concentrations of a substance as (time, node_id)."""
            name = f"ribasim_{substance[:20].replace(' ', '_')}"
            values = ds[name].transpose("nTimesDlwq", "ribasim_nNodes").to_numpy()
            return values[:, order].astype(np.float64)

        dfs = _write_concentration(
            model.results_path / "concentration.nc",
            time,
            node_id,
            substances,
            concentration,
            model.results,
            to_dataframe=to_input,
        )

    if to_input:
        # Optionally make the parsed results available as model input
        model.basin.concentration_external = _concat(dfs, ignore_index=True)

    return model


def _ordered_substances(model: ribasim.Model, substances: Collection[str]) -> list[str]:
    """Order the substances like the core: its own tracers, then those of the input tables.

    The substances that the core doesn't know of come last, sorted.
    """
    order = list(_CORE_TRACERS)
    for table in (
        model.basin.concentration_state,
        model.basin.concentration,
        model.basin.mass_load,
        model.flow_boundary.concentration,
        model.level_boundary.concentration,
    ):
        df = table.df
        if df is not None:
            # The core sorts the tables, and adds the substances in order of appearance
            order.extend(map(str, df.sort_values(table._sort_keys).substance.unique()))
    substances = set(map(str, substances))
    order = [substance for substance in dict.fromkeys(order) if substance in substances]
    return order + sorted(substances - set(order))


def _balanced_chunksizes(nlocation: int, ntime: int) -> tuple[int, int]:
    """Chunk sizes along the location and time dimensions, like the core.

    Reading all locations at one time, and one location at all times, then read about
    the same amount of data.
    """
    chunk_location = min(
        max(round(np.sqrt(_NC_CHUNK_LENGTH * nlocation / ntime)), 1), nlocation
    )
    chunk_time = min(max(_NC_CHUNK_LENGTH // chunk_location, 1), ntime)
    return chunk_location, chunk_time


def _write_concentration(
    path: Path,
    time: np.ndarray,
    node_id: np.ndarray,
    substances: list[str],
    concentration: Callable[[str], np.ndarray],
    results: Results,
    to_dataframe: bool = False,
) -> list[pd.DataFrame]:
    """Write the Basin concentrations to NetCDF, like the core writes `concentration.nc`.

    The concentrations of each substance are given as (time, node_id) by the function
    `concentration`, and written one substance at a time to limit the memory use. If
    `to_dataframe` is true, they are also returned as one DataFrame per substance, in the
    format of the `Basin / concentration_external` table.
    """
    ntime = len(time)
    nnode = len(node_id)
    # As the core, compress all variables, and shuffle and quantize the concentrations
    compression: Literal["zlib"] | None = "zlib" if results.compression else None
    complevel = cast(Any, results.compression_level)
    quantize = results.compression and results.significant_bits > 0
    chunk_location, chunk_time = _balanced_chunksizes(nnode, ntime)

    path.parent.mkdir(parents=True, exist_ok=True)
    dfs = []
    with netCDF4.Dataset(path, "w") as nc:
        nc.setncatts(
            {
                "Conventions": "CF-1.12",
                "references": "https://ribasim.org",
                "ribasim_version": ribasim.__version__,
                "title": "Ribasim results: concentration",
            }
        )
        nc.createDimension("time", ntime)
        nc.createDimension("node_id", nnode)
        nc.createDimension("substance", len(substances))

        var = nc.createVariable(
            "time", "f8", ("time",), compression, complevel=complevel, shuffle=False
        )
        var.setncatts(
            {
                "axis": "T",
                "calendar": "standard",
                "standard_name": "time",
                "long_name": "time",
                "units": "days since 1900-01-01 00:00:00",
            }
        )
        var[:] = (time - np.datetime64("1900-01-01")) / np.timedelta64(1, "D")

        var = nc.createVariable(
            "node_id",
            "i4",
            ("node_id",),
            compression,
            complevel=complevel,
            shuffle=False,
        )
        var.setncatts({"cf_role": "timeseries_id", "long_name": "node identifier"})
        var[:] = node_id

        var = nc.createVariable("substance", str, ("substance",))
        var.setncatts({"standard_name": "realization", "long_name": "substance name"})
        var[:] = np.array(substances, dtype=object)

        var = nc.createVariable(
            "concentration",
            "f8",
            ("time", "substance", "node_id"),
            compression,
            complevel=complevel,
            shuffle=quantize,
            chunksizes=(chunk_time, 1, chunk_location) if results.compression else None,
            significant_digits=results.significant_bits if quantize else None,
            quantize_mode="BitRound",
        )
        var.setncatts(
            {
                "units": "g m-3",
                "standard_name": "mass_concentration_of_substance_in_water",
                "long_name": "mass concentration",
            }
        )
        for i, substance in enumerate(substances):
            values = concentration(substance)
            var[:, i, :] = values
            if to_dataframe:
                dfs.append(
                    pd.DataFrame(
                        {
                            "node_id": np.tile(node_id, ntime),
                            "time": np.repeat(time, nnode),
                            "substance": substance,
                            "concentration": values.ravel(),
                        }
                    )
                )
    return dfs


if __name__ == "__main__":
    # Parse Delwaq output

    parser = argparse.ArgumentParser(
        description="Parse Delwaq results from `generate` and save the results back to Ribasim."
    )
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
