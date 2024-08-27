# Table for connectivity
# "basin": ["linear_resistance"] means that the downstream of basin can be linear_resistance only
connectivity = {
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
    "FLowDemand": [
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
