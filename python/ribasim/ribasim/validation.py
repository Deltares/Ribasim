# Automatically generated file. Do not modify.

# Table for connectivity
# "Basin": ["LinearResistance"] means that the downstream of basin can be LinearResistance only
node_type_connectivity: dict[str, list[str]] = {
    "Basin": [
        "LinearResistance",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
        "Outlet",
        "UserDemand",
        "Junction",
    ],
    "ContinuousControl": [
        "Pump",
        "Outlet",
    ],
    "DiscreteControl": [
        "Pump",
        "Outlet",
        "TabulatedRatingCurve",
        "LinearResistance",
        "ManningResistance",
        "PidControl",
    ],
    "FlowBoundary": [
        "Basin",
        "Terminal",
        "LevelBoundary",
        "Junction",
    ],
    "FlowDemand": [
        "LinearResistance",
        "ManningResistance",
        "TabulatedRatingCurve",
        "Pump",
        "Outlet",
    ],
    "Junction": [
        "Basin",
        "Junction",
        "LinearResistance",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
        "Outlet",
        "UserDemand",
        "Terminal",
    ],
    "LevelBoundary": [
        "LinearResistance",
        "Pump",
        "Outlet",
        "TabulatedRatingCurve",
    ],
    "LevelDemand": [
        "Basin",
    ],
    "LinearResistance": [
        "Basin",
        "LevelBoundary",
        "Junction",
    ],
    "ManningResistance": [
        "Basin",
        "Junction",
    ],
    "Outlet": [
        "Basin",
        "Terminal",
        "LevelBoundary",
        "Junction",
    ],
    "PidControl": [
        "Pump",
        "Outlet",
    ],
    "Pump": [
        "Basin",
        "Terminal",
        "LevelBoundary",
        "Junction",
    ],
    "TabulatedRatingCurve": [
        "Basin",
        "Terminal",
        "LevelBoundary",
        "Junction",
    ],
    "Terminal": [],
    "UserDemand": [
        "Basin",
        "Terminal",
        "LevelBoundary",
        "Junction",
    ],
}


# Function to validate connection
def can_connect(node_type_up: str, node_type_down: str) -> bool:
    if node_type_up in node_type_connectivity:
        return node_type_down in node_type_connectivity[node_type_up]
    return False


flow_link_neighbor_amount: dict[str, list[int]] = {
    "Basin": [0, 9223372036854775807, 0, 9223372036854775807],
    "ContinuousControl": [0, 0, 0, 0],
    "DiscreteControl": [0, 0, 0, 0],
    "FlowBoundary": [0, 0, 1, 1],
    "FlowDemand": [0, 0, 0, 0],
    "Junction": [1, 9223372036854775807, 1, 9223372036854775807],
    "LevelBoundary": [0, 9223372036854775807, 0, 9223372036854775807],
    "LevelDemand": [0, 0, 0, 0],
    "LinearResistance": [1, 1, 1, 1],
    "ManningResistance": [1, 1, 1, 1],
    "Outlet": [1, 1, 1, 1],
    "PidControl": [0, 0, 0, 0],
    "Pump": [1, 1, 1, 1],
    "TabulatedRatingCurve": [1, 1, 1, 1],
    "Terminal": [1, 9223372036854775807, 0, 0],
    "UserDemand": [1, 1, 1, 1],
}

control_link_neighbor_amount: dict[str, list[int]] = {
    "Basin": [0, 1, 0, 0],
    "ContinuousControl": [0, 0, 1, 9223372036854775807],
    "DiscreteControl": [0, 0, 1, 9223372036854775807],
    "FlowBoundary": [0, 0, 0, 0],
    "FlowDemand": [0, 0, 1, 1],
    "Junction": [0, 0, 0, 0],
    "LevelBoundary": [0, 0, 0, 0],
    "LevelDemand": [0, 0, 1, 9223372036854775807],
    "LinearResistance": [0, 1, 0, 0],
    "ManningResistance": [0, 1, 0, 0],
    "Outlet": [0, 2, 0, 0],
    "PidControl": [0, 1, 1, 1],
    "Pump": [0, 2, 0, 0],
    "TabulatedRatingCurve": [0, 1, 0, 0],
    "Terminal": [0, 0, 0, 0],
    "UserDemand": [0, 0, 0, 0],
}
