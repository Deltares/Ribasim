"""Sum Wflow land and river discharge over grid cells for each timestep."""

import argparse
import csv
from pathlib import Path

import xarray as xr

DEFAULT_INPUT = (
    Path(__file__).resolve().parent
    / "models"
    / "wflow_piave"
    / "run_default"
    / "output-piave.nc"
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sum q_av_river and q_av_land over spatial cells per timestep."
    )
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        default=DEFAULT_INPUT,
        help=f"Input Wflow NetCDF file (default: {DEFAULT_INPUT})",
    )
    parser.add_argument(
        "--output-csv",
        type=Path,
        help="Output CSV path (default: q_av_flow_sums.csv beside the input file).",
    )
    args = parser.parse_args()

    input_path = args.input.resolve()
    if not input_path.is_file():
        raise FileNotFoundError(f"Wflow output NetCDF not found: {input_path}")

    output_path = (
        args.output_csv.resolve()
        if args.output_csv is not None
        else input_path.with_name("q_av_flow_sums.csv")
    )

    with xr.open_dataset(input_path) as dataset:
        variables = ("q_av_river", "q_av_land")
        for variable in variables:
            if variable not in dataset:
                raise KeyError(f"{variable!r} not found in {input_path}")
            if "time" not in dataset[variable].dims:
                raise ValueError(f"{variable!r} has no 'time' dimension")

        flow_sums = {}
        cell_masks = {}
        for variable in variables:
            flow = dataset[variable]
            spatial_dims = [dim for dim in flow.dims if dim != "time"]
            if set(spatial_dims) != {"lon", "lat"}:
                raise ValueError(
                    f"Expected {variable} dimensions lon, lat, and time; "
                    f"found {flow.dims}"
                )

            flow_sums[variable] = flow.sum(dim=spatial_dims, skipna=True).load()
            cell_masks[variable] = flow.notnull()

        river_valid = cell_masks["q_av_river"]
        land_valid = cell_masks["q_av_land"]
        river_mask = river_valid.any(dim="time")
        land_mask = land_valid.any(dim="time")
        river_mask_static = bool((river_valid == river_mask).all().item())
        land_mask_static = bool((land_valid == land_mask).all().item())
        river_cells = int(river_mask.sum().item())
        land_cells = int(land_mask.sum().item())
        overlapping_cells = int((river_mask & land_mask).sum().item())
        unclassified_cells = int((~(river_mask | land_mask)).sum().item())
        complementary_masks = (
            river_mask_static
            and land_mask_static
            and overlapping_cells == 0
            and unclassified_cells == 0
        )
        times = dataset["time"].values

    with output_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["time", "q_av_river_sum_m3_s", "q_av_land_sum_m3_s"])
        writer.writerows(
            (
                str(time),
                float(river_sum),
                float(land_sum),
            )
            for time, river_sum, land_sum in zip(
                times,
                flow_sums["q_av_river"].values,
                flow_sums["q_av_land"].values,
                strict=True,
            )
        )

    print(f"Wrote {len(times)} timestep sums to {output_path}")
    print(
        "River/land cell masks static over time: "
        f"{river_mask_static}/{land_mask_static}"
    )
    print(
        "Cell masks complementary over the grid: "
        f"{complementary_masks} "
        f"(river cells: {river_cells}, land cells: {land_cells}, "
        f"overlap: {overlapping_cells}, neither: {unclassified_cells})"
    )
    for variable in ("q_av_river", "q_av_land"):
        totals = flow_sums[variable].values
        print(
            f"{variable} first/last timestep sums: "
            f"{float(totals[0]):g} / {float(totals[-1]):g} m3 s-1"
        )


if __name__ == "__main__":
    main()
