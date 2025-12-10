__version__ = "2025.6.0"
__schema_version__ = 9

from pyogrio import set_gdal_config_options

from ribasim.cli import run_ribasim
from ribasim.config import Allocation, Logging, Node, Solver
from ribasim.geometry.link import LinkTable
from ribasim.model import Model

y, m = map(int, __version__.split(".")[:2])
fake_date = f"{y}-{m}-1T00:00:00Z"

set_gdal_config_options(
    {
        "OGR_CURRENT_DATE": fake_date,  # %Y-%m-%dT%H:%M:%fZ
    }
)

__all__ = [
    "Allocation",
    "LinkTable",
    "Logging",
    "Model",
    "Node",
    "Solver",
    "run_ribasim",
]
