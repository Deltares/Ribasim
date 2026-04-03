from typing import Any

from ribasim.geometry import BasinAreaSchema
from ribasim.input_base import SpatialTableModel, TableModel
from ribasim.schemas import (
    BasinConcentrationExternalSchema,
    BasinConcentrationSchema,
    BasinConcentrationStateSchema,
    BasinMassLoadSchema,
    BasinProfileSchema,
    BasinStateSchema,
    BasinStaticSchema,
    BasinSubgridSchema,
    BasinSubgridTimeSchema,
    BasinTimeSchema,
)

__all__ = [
    "Area",
    "Concentration",
    "Profile",
    "State",
    "Static",
    "Subgrid",
    "SubgridTime",
    "Time",
]


class Static(TableModel[BasinStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[BasinTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class State(TableModel[BasinStateSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Profile(TableModel[BasinProfileSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Subgrid(TableModel[BasinSubgridSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class SubgridTime(TableModel[BasinSubgridTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Area(SpatialTableModel[BasinAreaSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Concentration(TableModel[BasinConcentrationSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class ConcentrationExternal(TableModel[BasinConcentrationExternalSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class ConcentrationState(TableModel[BasinConcentrationStateSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class MassLoad(TableModel[BasinMassLoadSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
