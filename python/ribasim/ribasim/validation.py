# Automatically generated file. Do not modify.

# Table for connectivity
# "Basin": ["LinearResistance"] means that the downstream of basin can be LinearResistance only

connectivity: dict[str, list[str]] = {
    "PidControl": [
        "Outlet",
        "Pump",
    ],
    "LevelBoundary": [
        "Outlet",
        "TabulatedRatingCurve",
        "LinearResistance",
        "Pump",
    ],
    "Pump": [
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "UserDemand": [
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "TabulatedRatingCurve": [
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "FlowDemand": [
        "LinearResistance",
        "Outlet",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "FlowBoundary": [
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "Basin": [
        "LinearResistance",
        "UserDemand",
        "Outlet",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "ManningResistance": [
        "Basin",
    ],
    "LevelDemand": [
        "Basin",
    ],
    "DiscreteControl": [
        "LinearResistance",
        "PidControl",
        "Outlet",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "Outlet": [
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "ContinuousControl": [
        "Outlet",
        "Pump",
    ],
    "LinearResistance": [
        "LevelBoundary",
        "Basin",
    ],
    "Terminal": [],
}


# Function to validate connection
def can_connect(node_up: str, node_down: str) -> bool:
    if node_up in connectivity:
        return node_down in connectivity[node_up]
    return False


flow_edge_amount: dict[str, list[int]] = {
    "PidControl": [0, 0, 0, 0],
    "LevelBoundary": [0, 9223372036854775807, 0, 9223372036854775807],
    "Pump": [1, 1, 1, 1],
    "UserDemand": [1, 1, 1, 1],
    "TabulatedRatingCurve": [1, 1, 1, 1],
    "FlowDemand": [0, 0, 0, 0],
    "FlowBoundary": [0, 0, 1, 9223372036854775807],
    "Basin": [0, 9223372036854775807, 0, 9223372036854775807],
    "ManningResistance": [1, 1, 1, 1],
    "LevelDemand": [0, 0, 0, 0],
    "DiscreteControl": [0, 0, 0, 0],
    "Outlet": [1, 1, 1, 1],
    "ContinuousControl": [0, 0, 0, 0],
    "LinearResistance": [1, 1, 1, 1],
    "Terminal": [1, 9223372036854775807, 0, 0],
}

control_edge_amount: dict[str, list[int]] = {
    "PidControl": [0, 1, 1, 1],
    "LevelBoundary": [0, 0, 0, 0],
    "Pump": [0, 1, 0, 0],
    "UserDemand": [0, 0, 0, 0],
    "TabulatedRatingCurve": [0, 1, 0, 0],
    "FlowDemand": [0, 0, 1, 1],
    "FlowBoundary": [0, 0, 0, 0],
    "Basin": [0, 1, 0, 0],
    "ManningResistance": [0, 1, 0, 0],
    "LevelDemand": [0, 0, 1, 9223372036854775807],
    "DiscreteControl": [0, 0, 1, 9223372036854775807],
    "Outlet": [0, 1, 0, 0],
    "ContinuousControl": [0, 0, 1, 9223372036854775807],
    "LinearResistance": [0, 1, 0, 0],
    "Terminal": [0, 0, 0, 0],
}
