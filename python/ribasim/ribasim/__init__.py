__version__ = "2026.1.0-rc1"
__schema_version__ = 10

from pyogrio import set_gdal_config_options

from ribasim.cli import run_ribasim
from ribasim.config import Allocation, Logging, Node, Solver
from ribasim.db_utils import fake_date
from ribasim.geometry.link import LinkTable
from ribasim.model import Model

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
