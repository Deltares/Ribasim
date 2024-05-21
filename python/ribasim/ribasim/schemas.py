# Automatically generated file. Do not modify.

import pandera as pa
from pandera.dtypes import Int32, Timestamp
from pandera.typing import Series


class _BaseSchema(pa.DataFrameModel):
    class Config:
        add_missing_columns = True
        coerce = True


class BasinConcentrationExternalSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    substance: Series[str] = pa.Field(nullable=False)
    concentration: Series[float] = pa.Field(nullable=True)


class BasinConcentrationStateSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    substance: Series[str] = pa.Field(nullable=False)
    concentration: Series[float] = pa.Field(nullable=True)


class BasinConcentrationSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    substance: Series[str] = pa.Field(nullable=False)
    drainage: Series[float] = pa.Field(nullable=True)
    precipitation: Series[float] = pa.Field(nullable=True)


class BasinProfileSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    area: Series[float] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)


class BasinStateSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    level: Series[float] = pa.Field(nullable=False)


class BasinStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    drainage: Series[float] = pa.Field(nullable=True)
    potential_evaporation: Series[float] = pa.Field(nullable=True)
    infiltration: Series[float] = pa.Field(nullable=True)
    precipitation: Series[float] = pa.Field(nullable=True)
    urban_runoff: Series[float] = pa.Field(nullable=True)


class BasinSubgridSchema(_BaseSchema):
    subgrid_id: Series[Int32] = pa.Field(nullable=False, default=0)
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    basin_level: Series[float] = pa.Field(nullable=False)
    subgrid_level: Series[float] = pa.Field(nullable=False)


class BasinTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    drainage: Series[float] = pa.Field(nullable=True)
    potential_evaporation: Series[float] = pa.Field(nullable=True)
    infiltration: Series[float] = pa.Field(nullable=True)
    precipitation: Series[float] = pa.Field(nullable=True)
    urban_runoff: Series[float] = pa.Field(nullable=True)


class DiscreteControlConditionSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    compound_variable_id: Series[Int32] = pa.Field(nullable=False, default=0)
    greater_than: Series[float] = pa.Field(nullable=False)


class DiscreteControlLogicSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    truth_state: Series[str] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=False)


class DiscreteControlVariableSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    compound_variable_id: Series[Int32] = pa.Field(nullable=False, default=0)
    listen_node_type: Series[str] = pa.Field(nullable=False)
    listen_node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    variable: Series[str] = pa.Field(nullable=False)
    weight: Series[float] = pa.Field(nullable=True)
    look_ahead: Series[float] = pa.Field(nullable=True)


class FlowBoundaryConcentrationSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    substance: Series[str] = pa.Field(nullable=False)
    concentration: Series[float] = pa.Field(nullable=False)


class FlowBoundaryStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)


class FlowBoundaryTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)


class FlowDemandStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    demand: Series[float] = pa.Field(nullable=False)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)


class FlowDemandTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    demand: Series[float] = pa.Field(nullable=False)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)


class FractionalFlowStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    fraction: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)


class LevelBoundaryConcentrationSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    substance: Series[str] = pa.Field(nullable=False)
    concentration: Series[float] = pa.Field(nullable=False)


class LevelBoundaryStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    level: Series[float] = pa.Field(nullable=False)


class LevelBoundaryTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)


class LevelDemandStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    min_level: Series[float] = pa.Field(nullable=True)
    max_level: Series[float] = pa.Field(nullable=True)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)


class LevelDemandTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    min_level: Series[float] = pa.Field(nullable=True)
    max_level: Series[float] = pa.Field(nullable=True)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)


class LinearResistanceStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    resistance: Series[float] = pa.Field(nullable=False)
    max_flow_rate: Series[float] = pa.Field(nullable=True)
    control_state: Series[str] = pa.Field(nullable=True)


class ManningResistanceStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    length: Series[float] = pa.Field(nullable=False)
    manning_n: Series[float] = pa.Field(nullable=False)
    profile_width: Series[float] = pa.Field(nullable=False)
    profile_slope: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)


class OutletStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)
    min_flow_rate: Series[float] = pa.Field(nullable=True)
    max_flow_rate: Series[float] = pa.Field(nullable=True)
    min_crest_level: Series[float] = pa.Field(nullable=True)
    control_state: Series[str] = pa.Field(nullable=True)


class PidControlStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    listen_node_type: Series[str] = pa.Field(nullable=False)
    listen_node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    target: Series[float] = pa.Field(nullable=False)
    proportional: Series[float] = pa.Field(nullable=False)
    integral: Series[float] = pa.Field(nullable=False)
    derivative: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)


class PidControlTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    listen_node_type: Series[str] = pa.Field(nullable=False)
    listen_node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    target: Series[float] = pa.Field(nullable=False)
    proportional: Series[float] = pa.Field(nullable=False)
    integral: Series[float] = pa.Field(nullable=False)
    derivative: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)


class PumpStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)
    min_flow_rate: Series[float] = pa.Field(nullable=True)
    max_flow_rate: Series[float] = pa.Field(nullable=True)
    control_state: Series[str] = pa.Field(nullable=True)


class TabulatedRatingCurveStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    level: Series[float] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)


class TabulatedRatingCurveTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)


class TerminalStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)


class UserDemandStaticSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    active: Series[pa.BOOL] = pa.Field(nullable=True)
    demand: Series[float] = pa.Field(nullable=True)
    return_factor: Series[float] = pa.Field(nullable=False)
    min_level: Series[float] = pa.Field(nullable=False)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)


class UserDemandTimeSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    time: Series[Timestamp] = pa.Field(nullable=False)
    demand: Series[float] = pa.Field(nullable=False)
    return_factor: Series[float] = pa.Field(nullable=False)
    min_level: Series[float] = pa.Field(nullable=False)
    priority: Series[Int32] = pa.Field(nullable=False, default=0)
