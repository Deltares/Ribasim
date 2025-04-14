__version__ = "2025.3.0"
# Keep synced write_schema_version in ribasim_qgis/core/geopackage.py
__schema_version__ = 5

import logging

logging.getLogger("datacompy").setLevel(logging.ERROR)

from ribasim.config import Allocation, Logging, Node, Solver  # noqa: E402
from ribasim.geometry.link import LinkTable  # noqa: E402
from ribasim.model import Model  # noqa: E402

__all__ = ["LinkTable", "Allocation", "Logging", "Model", "Solver", "Node"]
