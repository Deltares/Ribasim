# Automatically generated file.
# DO NOT MODIFY.

import pandera as pa
from pandera.typing import Series


class BasinProfileSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    area: Series[float] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class BasinStateSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class BasinStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    drainage: Series[float] = pa.Field(nullable=True)
    potential_evaporation: Series[float] = pa.Field(nullable=True)
    infiltration: Series[float] = pa.Field(nullable=True)
    precipitation: Series[float] = pa.Field(nullable=True)
    urban_runoff: Series[float] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class BasinSubgridSchema(pa.DataFrameModel):
    subgrid_id: Series[int] = pa.Field(nullable=False)
    node_id: Series[int] = pa.Field(nullable=False)
    basin_level: Series[float] = pa.Field(nullable=False)
    subgrid_level: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class BasinTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    drainage: Series[float] = pa.Field(nullable=True)
    potential_evaporation: Series[float] = pa.Field(nullable=True)
    infiltration: Series[float] = pa.Field(nullable=True)
    precipitation: Series[float] = pa.Field(nullable=True)
    urban_runoff: Series[float] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class DiscreteControlConditionSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    listen_feature_id: Series[int] = pa.Field(nullable=False)
    variable: Series[str] = pa.Field(nullable=False)
    greater_than: Series[float] = pa.Field(nullable=False)
    look_ahead: Series[float] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class DiscreteControlLogicSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    truth_state: Series[str] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class EdgeSchema(pa.DataFrameModel):
    fid: Series[int] = pa.Field(nullable=False)
    name: Series[str] = pa.Field(nullable=False)
    from_node_id: Series[int] = pa.Field(nullable=False)
    to_node_id: Series[int] = pa.Field(nullable=False)
    edge_type: Series[str] = pa.Field(nullable=False)
    allocation_network_id: Series[int] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class FlowBoundaryStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class FlowBoundaryTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class FractionalFlowStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    fraction: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class LevelBoundaryStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    level: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class LevelBoundaryTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class LinearResistanceStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    resistance: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class ManningResistanceStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    length: Series[float] = pa.Field(nullable=False)
    manning_n: Series[float] = pa.Field(nullable=False)
    profile_width: Series[float] = pa.Field(nullable=False)
    profile_slope: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class NodeSchema(pa.DataFrameModel):
    fid: Series[int] = pa.Field(nullable=False)
    name: Series[str] = pa.Field(nullable=False)
    type: Series[str] = pa.Field(nullable=False)
    allocation_network_id: Series[int] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class OutletStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)
    min_flow_rate: Series[float] = pa.Field(nullable=True)
    max_flow_rate: Series[float] = pa.Field(nullable=True)
    min_crest_level: Series[float] = pa.Field(nullable=True)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class PidControlStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    listen_node_id: Series[int] = pa.Field(nullable=False)
    target: Series[float] = pa.Field(nullable=False)
    proportional: Series[float] = pa.Field(nullable=False)
    integral: Series[float] = pa.Field(nullable=False)
    derivative: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class PidControlTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    listen_node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    target: Series[float] = pa.Field(nullable=False)
    proportional: Series[float] = pa.Field(nullable=False)
    integral: Series[float] = pa.Field(nullable=False)
    derivative: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class PumpStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    flow_rate: Series[float] = pa.Field(nullable=False)
    min_flow_rate: Series[float] = pa.Field(nullable=True)
    max_flow_rate: Series[float] = pa.Field(nullable=True)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class TabulatedRatingCurveStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    level: Series[float] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)
    control_state: Series[str] = pa.Field(nullable=True)

    class Config:
        add_missing_columns = True
        coerce = True


class TabulatedRatingCurveTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    level: Series[float] = pa.Field(nullable=False)
    flow_rate: Series[float] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class TerminalStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class UserStaticSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    active: Series[bool] = pa.Field(nullable=True)
    demand: Series[float] = pa.Field(nullable=False)
    return_factor: Series[float] = pa.Field(nullable=False)
    min_level: Series[float] = pa.Field(nullable=False)
    priority: Series[int] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True


class UserTimeSchema(pa.DataFrameModel):
    node_id: Series[int] = pa.Field(nullable=False)
    time: Series[str] = pa.Field(nullable=False)
    demand: Series[float] = pa.Field(nullable=False)
    return_factor: Series[float] = pa.Field(nullable=False)
    min_level: Series[float] = pa.Field(nullable=False)
    priority: Series[int] = pa.Field(nullable=False)

    class Config:
        add_missing_columns = True
        coerce = True
