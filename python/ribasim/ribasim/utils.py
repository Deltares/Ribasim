from collections.abc import Sequence


def prefix_column(
    column: str, record_columns: Sequence[str], prefix: str = "meta_"
) -> str:
    """Prefix column name with `prefix` if not in record_columns."""
    if (
        len(record_columns) > 0
        and column not in record_columns
        and column != "fid"
        and not column.startswith(prefix)
    ):
        column = f"{prefix}{column}"
    return column
