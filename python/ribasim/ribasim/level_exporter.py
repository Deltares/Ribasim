from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import LevelExporterStaticSchema  # type: ignore


class LevelExporter(TableModel):
    """The level exporter export Ribasim water levels."""

    static: DataFrame[LevelExporterStaticSchema]

    def sort(self):
        self.static.sort_values(
            ["name", "element_id", "node_id", "basin_level"],
            ignore_index=True,
            inplace=True,
        )
