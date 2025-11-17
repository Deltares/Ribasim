__version__ = "2025.6.0"
__schema_version__ = 8

import logging

logging.getLogger("datacompy").setLevel(logging.ERROR)

from ribasim.cli import run_ribasim  # noqa: E402
from ribasim.config import Allocation, Logging, Node, Solver  # noqa: E402
from ribasim.geometry.link import LinkTable  # noqa: E402
from ribasim.model import Model  # noqa: E402

__all__ = [
    "Allocation",
    "LinkTable",
    "Logging",
    "Model",
    "Node",
    "Solver",
    "run_ribasim",
]
