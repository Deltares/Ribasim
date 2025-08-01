# Automatically generated file. Do not modify.

# Table for connectivity
# "Basin": ["LinearResistance"] means that the downstream of basin can be LinearResistance only
node_type_connectivity: dict[str, list[str]] = {
    "Basin": [
        "LinearResistance",
        "UserDemand",
        "Junction",
        "Outlet",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "ContinuousControl": [
        "Outlet",
        "Pump",
    ],
    "DiscreteControl": [
        "LinearResistance",
        "PidControl",
        "Outlet",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "FlowBoundary": [
        "Junction",
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
    "Junction": [
        "LinearResistance",
        "UserDemand",
        "Terminal",
        "Junction",
        "Outlet",
        "Basin",
        "TabulatedRatingCurve",
        "ManningResistance",
        "Pump",
    ],
    "LevelBoundary": [
        "Outlet",
        "TabulatedRatingCurve",
        "LinearResistance",
        "Pump",
    ],
    "LevelDemand": [
        "Basin",
    ],
    "LinearResistance": [
        "Junction",
        "LevelBoundary",
        "Basin",
    ],
    "ManningResistance": [
        "Junction",
        "Basin",
    ],
    "Outlet": [
        "Junction",
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "PidControl": [
        "Outlet",
        "Pump",
    ],
    "Pump": [
        "Junction",
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "TabulatedRatingCurve": [
        "Junction",
        "LevelBoundary",
        "Basin",
        "Terminal",
    ],
    "Terminal": [],
    "UserDemand": [
        "Junction",
        "LevelBoundary",
        "Basin",
        "Terminal",
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
    "Outlet": [0, 1, 0, 0],
    "PidControl": [0, 1, 1, 1],
    "Pump": [0, 1, 0, 0],
    "TabulatedRatingCurve": [0, 1, 0, 0],
    "Terminal": [0, 0, 0, 0],
    "UserDemand": [0, 0, 0, 0],
}
