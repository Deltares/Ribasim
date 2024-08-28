import numpy as np

# Table for connectivity
# "Basin": ["LinearResistance"] means that the downstream of basin can be LinearResistance only
connectivity: dict[str, list[str]] = {
    "Basin": [
        "LinearResistance",
        "ManningResistance",
        "TabulatedRatingCurve",
        "Pump",
        "Outlet",
        "UserDemand",
    ],
    "LinearResistance": ["Basin", "LevelBoundary"],
    "ManningResistance": ["Basin"],
    "TabulatedRatingCurve": ["Basin", "Terminal", "LevelBoundary"],
    "LevelBoundary": ["LinearResistance", "Pump", "Outlet", "TabulatedRatingCurve"],
    "FlowBoundary": ["Basin", "Terminal", "LevelBoundary"],
    "Pump": ["Basin", "Terminal", "LevelBoundary"],
    "Outlet": ["Basin", "Terminal", "LevelBoundary"],
    "Terminal": [],
    "DiscreteControl": [
        "Pump",
        "Outlet",
        "TabulatedRatingCurve",
        "LinearResistance",
        "ManningResistance",
        "PidControl",
    ],
    "ContinuousControl": ["Pump", "Outlet"],
    "PidControl": ["Pump", "Outlet"],
    "UserDemand": ["Basin", "Terminal", "LevelBoundary"],
    "LevelDemand": ["Basin"],
    "FlowDemand": [
        "LinearResistance",
        "ManningResistance",
        "TabulatedRatingCurve",
        "Pump",
        "Outlet",
    ],
}


# Function to validate connection
def can_connect(node_up: str, node_down: str) -> bool:
    if node_up in connectivity:
        return node_down in connectivity[node_up]
    return False


flow_edge_amount: dict[str, list[int]] = {
    "Basin": [0, np.inf, 0, np.inf],
    "LinearResistance": [1, 1, 1, 1],
    "ManningResistance": [1, 1, 1, 1],
    "TabulatedRatingCurve": [1, 1, 1, np.inf],
    "LevelBoundary": [0, np.inf, 0, np.inf],
    "FlowBoundary": [0, 0, 1, np.inf],
    "Pump": [1, 1, 1, np.inf],
    "Outlet": [1, 1, 1, 1],
    "Terminal": [1, np.inf, 0, 0],
    "DiscreteControl": [0, 0, 0, 0],
    "ContinuousControl": [0, 0, 0, 0],
    "PidControl": [0, 0, 0, 0],
    "UserDemand": [1, 1, 1, 1],
    "LevelDemand": [0, 0, 0, 0],
    "FlowDemand": [0, 0, 0, 0],
}
