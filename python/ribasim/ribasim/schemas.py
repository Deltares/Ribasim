# Automatically generated file.
# DO NOT MODIFY.

from typing import Optional

import pandera as pa
from pandera.typing import Series


class BasinProfileSchema(pa.DataFrameModel):
    node_id: Series[int]
    area: Series[float]
    level: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class BasinStateSchema(pa.DataFrameModel):
    node_id: Series[int]
    level: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class BasinStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    drainage: Optional[Series[float]]
    potential_evaporation: Optional[Series[float]]
    infiltration: Optional[Series[float]]
    precipitation: Optional[Series[float]]
    urban_runoff: Optional[Series[float]]

    class Config:
        add_missing_columns = True
        coerce = True


class BasinSubgridSchema(pa.DataFrameModel):
    subgrid_id: Series[int]
    node_id: Series[int]
    basin_level: Series[float]
    subgrid_level: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class BasinTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    time: Series[str]
    drainage: Optional[Series[float]]
    potential_evaporation: Optional[Series[float]]
    infiltration: Optional[Series[float]]
    precipitation: Optional[Series[float]]
    urban_runoff: Optional[Series[float]]

    class Config:
        add_missing_columns = True
        coerce = True


class DiscreteControlConditionSchema(pa.DataFrameModel):
    node_id: Series[int]
    listen_feature_id: Series[int]
    variable: Series[str]
    greater_than: Series[float]
    look_ahead: Optional[Series[float]]

    class Config:
        add_missing_columns = True
        coerce = True


class DiscreteControlLogicSchema(pa.DataFrameModel):
    node_id: Series[int]
    truth_state: Series[str]
    control_state: Series[str]

    class Config:
        add_missing_columns = True
        coerce = True


class EdgeSchema(pa.DataFrameModel):
    fid: Series[int]
    name: Series[str]
    from_node_id: Series[int]
    to_node_id: Series[int]
    edge_type: Series[str]
    allocation_network_id: Optional[Series[int]]

    class Config:
        add_missing_columns = True
        coerce = True


class FlowBoundaryStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    flow_rate: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class FlowBoundaryTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    time: Series[str]
    flow_rate: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class FractionalFlowStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    fraction: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class LevelBoundaryStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    level: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class LevelBoundaryTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    time: Series[str]
    level: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class LinearResistanceStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    resistance: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class ManningResistanceStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    length: Series[float]
    manning_n: Series[float]
    profile_width: Series[float]
    profile_slope: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class NodeSchema(pa.DataFrameModel):
    fid: Series[int]
    name: Series[str]
    type: Series[str]
    allocation_network_id: Optional[Series[int]]

    class Config:
        add_missing_columns = True
        coerce = True


class OutletStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    flow_rate: Series[float]
    min_flow_rate: Optional[Series[float]]
    max_flow_rate: Optional[Series[float]]
    min_crest_level: Optional[Series[float]]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class PidControlStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    listen_node_id: Series[int]
    target: Series[float]
    proportional: Series[float]
    integral: Series[float]
    derivative: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class PidControlTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    listen_node_id: Series[int]
    time: Series[str]
    target: Series[float]
    proportional: Series[float]
    integral: Series[float]
    derivative: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class PumpStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    flow_rate: Series[float]
    min_flow_rate: Optional[Series[float]]
    max_flow_rate: Optional[Series[float]]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class TabulatedRatingCurveStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    level: Series[float]
    flow_rate: Series[float]
    control_state: Optional[Series[str]]

    class Config:
        add_missing_columns = True
        coerce = True


class TabulatedRatingCurveTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    time: Series[str]
    level: Series[float]
    flow_rate: Series[float]

    class Config:
        add_missing_columns = True
        coerce = True


class TerminalStaticSchema(pa.DataFrameModel):
    node_id: Series[int]

    class Config:
        add_missing_columns = True
        coerce = True


class UserStaticSchema(pa.DataFrameModel):
    node_id: Series[int]
    active: Optional[Series[bool]]
    demand: Series[float]
    return_factor: Series[float]
    min_level: Series[float]
    priority: Series[int]

    class Config:
        add_missing_columns = True
        coerce = True


class UserTimeSchema(pa.DataFrameModel):
    node_id: Series[int]
    time: Series[str]
    demand: Series[float]
    return_factor: Series[float]
    min_level: Series[float]
    priority: Series[int]

    class Config:
        add_missing_columns = True
        coerce = True
