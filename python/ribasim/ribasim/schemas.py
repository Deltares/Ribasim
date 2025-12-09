# Automatically generated file. Do not modify.

from collections.abc import Callable
from typing import Any

import numpy as np
import pandas as pd
import pandera.pandas as pa
from pandera.dtypes import Int32
from pandera.typing import Index

from ribasim import migrations


class _BaseSchema(pa.DataFrameModel):
    class Config:
        add_missing_columns = True
        coerce = True

    @classmethod
    def _index_name(cls) -> str:
        return "fid"

    @pa.dataframe_parser
    @classmethod
    def _name_index(cls, df):
        df.index.name = cls._index_name()
        return df

    @classmethod
    def migrate(cls, df: Any, schema_version: int) -> Any:
        f: Callable[[Any, Any], Any] = getattr(
            migrations, str(cls.__name__).lower() + "_migration", lambda x, _: x
        )
        return f(df, schema_version)


class BasinConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    substance: pd.StringDtype = pa.Field(nullable=False)
    drainage: float = pa.Field(nullable=True)
    precipitation: float = pa.Field(nullable=True)
    surface_runoff: float = pa.Field(nullable=True)


class BasinConcentrationExternalSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    substance: pd.StringDtype = pa.Field(nullable=False)
    concentration: float = pa.Field(nullable=True)


class BasinConcentrationStateSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    substance: pd.StringDtype = pa.Field(nullable=False)
    concentration: float = pa.Field(nullable=True)


class BasinProfileSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    area: float = pa.Field(nullable=True)
    level: float = pa.Field(nullable=False)
    storage: float = pa.Field(nullable=True)


class BasinStateSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    level: float = pa.Field(nullable=False)


class BasinStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    drainage: float = pa.Field(nullable=True)
    potential_evaporation: float = pa.Field(nullable=True)
    infiltration: float = pa.Field(nullable=True)
    precipitation: float = pa.Field(nullable=True)
    surface_runoff: float = pa.Field(nullable=True)


class BasinSubgridSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    subgrid_id: np.int32 = pa.Field(nullable=False)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    basin_level: float = pa.Field(nullable=False)
    subgrid_level: float = pa.Field(nullable=False)


class BasinSubgridTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    subgrid_id: np.int32 = pa.Field(nullable=False)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    basin_level: float = pa.Field(nullable=False)
    subgrid_level: float = pa.Field(nullable=False)


class BasinTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    drainage: float = pa.Field(nullable=True)
    potential_evaporation: float = pa.Field(nullable=True)
    infiltration: float = pa.Field(nullable=True)
    precipitation: float = pa.Field(nullable=True)
    surface_runoff: float = pa.Field(nullable=True)


class ContinuousControlFunctionSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    input: float = pa.Field(nullable=False)
    output: float = pa.Field(nullable=False)
    controlled_variable: pd.StringDtype = pa.Field(nullable=False)


class ContinuousControlVariableSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    listen_node_id: np.int32 = pa.Field(nullable=False)
    variable: pd.StringDtype = pa.Field(nullable=False)
    weight: float = pa.Field(nullable=True)
    look_ahead: float = pa.Field(nullable=True)


class DiscreteControlConditionSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    compound_variable_id: np.int32 = pa.Field(nullable=False)
    condition_id: np.int32 = pa.Field(nullable=False)
    threshold_high: float = pa.Field(nullable=False)
    threshold_low: float = pa.Field(nullable=True)
    time: pd.Timestamp = pa.Field(nullable=True)


class DiscreteControlLogicSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    truth_state: pd.StringDtype = pa.Field(nullable=False)
    control_state: pd.StringDtype = pa.Field(nullable=False)


class DiscreteControlVariableSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    compound_variable_id: np.int32 = pa.Field(nullable=False)
    listen_node_id: np.int32 = pa.Field(nullable=False)
    variable: pd.StringDtype = pa.Field(nullable=False)
    weight: float = pa.Field(nullable=True)
    look_ahead: float = pa.Field(nullable=True)


class FlowBoundaryConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    substance: pd.StringDtype = pa.Field(nullable=False)
    concentration: float = pa.Field(nullable=False)


class FlowBoundaryStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    flow_rate: float = pa.Field(nullable=False)


class FlowBoundaryTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    flow_rate: float = pa.Field(nullable=False)


class FlowDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    demand: float = pa.Field(nullable=False)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)


class FlowDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    demand: float = pa.Field(nullable=False)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)


class LevelBoundaryConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    substance: pd.StringDtype = pa.Field(nullable=False)
    concentration: float = pa.Field(nullable=False)


class LevelBoundaryStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    level: float = pa.Field(nullable=False)


class LevelBoundaryTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    level: float = pa.Field(nullable=False)


class LevelDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    min_level: float = pa.Field(nullable=True)
    max_level: float = pa.Field(nullable=True)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)


class LevelDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    min_level: float = pa.Field(nullable=True)
    max_level: float = pa.Field(nullable=True)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)


class LinearResistanceStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    resistance: float = pa.Field(nullable=False)
    max_flow_rate: float = pa.Field(nullable=True)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class ManningResistanceStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    length: float = pa.Field(nullable=False)
    manning_n: float = pa.Field(nullable=False)
    profile_width: float = pa.Field(nullable=False)
    profile_slope: float = pa.Field(nullable=False)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class OutletStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    flow_rate: float = pa.Field(nullable=False)
    min_flow_rate: float = pa.Field(nullable=True)
    max_flow_rate: float = pa.Field(nullable=True)
    min_upstream_level: float = pa.Field(nullable=True)
    max_downstream_level: float = pa.Field(nullable=True)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class OutletTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    flow_rate: float = pa.Field(nullable=False)
    min_flow_rate: float = pa.Field(nullable=True)
    max_flow_rate: float = pa.Field(nullable=True)
    min_upstream_level: float = pa.Field(nullable=True)
    max_downstream_level: float = pa.Field(nullable=True)


class PidControlStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    listen_node_id: np.int32 = pa.Field(nullable=False)
    target: float = pa.Field(nullable=False)
    proportional: float = pa.Field(nullable=False)
    integral: float = pa.Field(nullable=False)
    derivative: float = pa.Field(nullable=False)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class PidControlTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    listen_node_id: np.int32 = pa.Field(nullable=False)
    time: pd.Timestamp = pa.Field(nullable=False)
    target: float = pa.Field(nullable=False)
    proportional: float = pa.Field(nullable=False)
    integral: float = pa.Field(nullable=False)
    derivative: float = pa.Field(nullable=False)


class PumpStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    flow_rate: float = pa.Field(nullable=False)
    min_flow_rate: float = pa.Field(nullable=True)
    max_flow_rate: float = pa.Field(nullable=True)
    min_upstream_level: float = pa.Field(nullable=True)
    max_downstream_level: float = pa.Field(nullable=True)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class PumpTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    flow_rate: float = pa.Field(nullable=False)
    min_flow_rate: float = pa.Field(nullable=True)
    max_flow_rate: float = pa.Field(nullable=True)
    min_upstream_level: float = pa.Field(nullable=True)
    max_downstream_level: float = pa.Field(nullable=True)


class TabulatedRatingCurveStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    level: float = pa.Field(nullable=False)
    flow_rate: float = pa.Field(nullable=False)
    max_downstream_level: float = pa.Field(nullable=True)
    control_state: pd.StringDtype = pa.Field(nullable=True)


class TabulatedRatingCurveTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    level: float = pa.Field(nullable=False)
    flow_rate: float = pa.Field(nullable=False)
    max_downstream_level: float = pa.Field(nullable=True)


class UserDemandConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    substance: pd.StringDtype = pa.Field(nullable=False)
    concentration: float = pa.Field(nullable=False)


class UserDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    demand: float = pa.Field(nullable=True)
    return_factor: float = pa.Field(nullable=False)
    min_level: float = pa.Field(nullable=False)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)


class UserDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: np.int32 = pa.Field(nullable=False, default=0)
    time: pd.Timestamp = pa.Field(nullable=False)
    demand: float = pa.Field(nullable=False)
    return_factor: float = pa.Field(nullable=False)
    min_level: float = pa.Field(nullable=False)
    demand_priority: pd.Int32Dtype = pa.Field(nullable=True)
