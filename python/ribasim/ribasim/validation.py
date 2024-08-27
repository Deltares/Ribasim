# Table for connectivity
# "basin": ["linear_resistance"] means that the downstream of basin can be linear_resistance only
connectivity = {
    "basin": [
        "linear_resistance",
        "manning_resistance",
        "tabulated_rating_curve",
        "pump",
        "outlet",
        "user_demand",
    ],
    "linear_resistance": ["basin", "level_boundary"],
    "manning_resistance": ["basin"],
    "tabulated_rating_curve": ["basin", "terminal", "level_boundary"],
    "level_boundary": ["linear_resistance", "pump", "outlet", "tabulated_rating_curve"],
    "flow_boundary": ["basin", "terminal", "level_boundary"],
    "pump": ["basin", "terminal", "level_boundary"],
    "outlet": ["basin", "terminal", "level_boundary"],
    "terminal": [],
    "discrete_control": [
        "pump",
        "outlet",
        "tabulated_rating_curve",
        "linear_resistance",
        "manning_resistance",
        "pid_control",
    ],
    "continuous_control": ["pump", "outlet"],
    "pid_control": ["pump", "outlet"],
    "user_demand": ["basin", "terminal", "level_boundary"],
    "level_demand": ["basin"],
    "flow_demand": ["basin", "terminal", "level_boundary"],
}


# Function to validate connection
def can_connect(node_up: str, node_down: str) -> bool:
    if node_up in connectivity:
        return node_down in connectivity[node_up]
    return False
