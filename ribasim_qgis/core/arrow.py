import pandas as pd


def postprocess_concentration_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the concentration arrow data to a wide format."""
    ndf = pd.pivot_table(df, columns="substance", index=["time", "node_id"])
    ndf.columns = ndf.columns.droplevel(0)
    ndf.reset_index("node_id", inplace=True)
    return ndf


def postprocess_allocation_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation arrow data to a wide format by summing over priorities."""
    ndf = df.groupby(["time", "node_id"]).aggregate(
        {"demand": "sum", "allocated": "sum", "realized": "sum"}
    )
    ndf.reset_index("node_id", inplace=True)
    return ndf


def postprocess_allocation_flow_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation flow arrow data to a wide format by summing over priorities."""
    ndf = df.groupby(["time", "link_id"]).aggregate({"flow_rate": "sum"})
    # Drop Basin to Basin flows, as we can't join/visualize them
    ndf.drop(ndf[ndf.index.get_level_values("link_id") == 0].index, inplace=True)
    ndf.reset_index("link_id", inplace=True)
    return ndf


def postprocess_flow_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation flow arrow data to a wide format by summing over priorities."""
    ndf = df.set_index(pd.DatetimeIndex(df["time"]))
    ndf.drop(columns=["time", "from_node_id", "to_node_id"], inplace=True)
    return ndf
