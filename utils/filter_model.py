import argparse
from pathlib import Path

import pandas as pd
from ribasim import Model


def filter_time_tables(model: Model) -> Model:
    """
    Filter all time-based tables to only include rows within the simulation period.

    This function removes all rows from time tables where the time column
    is outside the range [model.starttime, model.endtime].

    If there is no timestamp on the start or endtime this can affect the results,
    because there won't be another entry to interpolate with.

    Parameters
    ----------
    model : Model
        The Ribasim model to filter

    Returns
    -------
    Model
        The filtered model
    """
    starttime = pd.Timestamp(model.starttime)
    endtime = pd.Timestamp(model.endtime)

    print(f"Filtering time tables to period: {starttime} to {endtime}")

    total_rows_removed = 0

    # Iterate over all node types in the model
    for sub in model._nodes():
        # Iterate over all tables in each node type
        for table in sub._tables():
            table_name = table.tablename()

            # Check if the table has data and a time column
            if table.df is not None and "time" in table.df.columns:
                original_count = len(table.df)

                # Convert time column to pandas Timestamp for comparison
                time_col = pd.to_datetime(table.df["time"])

                # Filter rows within the simulation period or with missing time values
                # Keep rows where time is within range OR time is missing (NaN)
                mask = (
                    (time_col >= starttime) & (time_col <= endtime)
                ) | time_col.isna()
                filtered_df = table.df[mask].copy()

                rows_removed = original_count - len(filtered_df)
                if rows_removed > 0:
                    print(
                        f"{table_name.ljust(35)} "
                        f"removed {rows_removed} / {original_count} rows "
                        f"({rows_removed / original_count * 100:.1f}%)"
                    )
                    total_rows_removed += rows_removed

                    # Update the table with filtered data
                    table.df = filtered_df

    print(f"Total rows removed across all time tables: {total_rows_removed}")
    return model


def main():
    parser = argparse.ArgumentParser(
        description="Filter Ribasim model time tables to simulation period."
    )
    parser.add_argument("input_toml", help="Path to input TOML file")
    parser.add_argument(
        "output_toml",
        nargs="?",
        help="Path to output TOML file (defaults to input_toml if not provided)",
    )

    args = parser.parse_args()

    input_path = Path(args.input_toml)
    # If no output path is provided, use the input path (in-place modification)
    output_path = Path(args.output_toml) if args.output_toml else input_path

    model = Model.read(input_path)

    # Filter the time tables
    filtered_model = filter_time_tables(model)

    filtered_model.write(output_path)


if __name__ == "__main__":
    main()
