# Automatically generated file.
# DO NOT MODIFY.

from datetime import datetime

from pydantic import Field

from ribasim.input_base import BaseModel


class BasinProfile(BaseModel):
    node_id: int
    area: float
    level: float
    remarks: str = Field("", description="a hack for pandera")


class BasinState(BaseModel):
    node_id: int
    level: float
    remarks: str = Field("", description="a hack for pandera")


class BasinStatic(BaseModel):
    node_id: int
    drainage: None | float = None
    potential_evaporation: None | float = None
    infiltration: None | float = None
    precipitation: None | float = None
    urban_runoff: None | float = None
    remarks: str = Field("", description="a hack for pandera")


class BasinSubgrid(BaseModel):
    subgrid_id: int
    node_id: int
    basin_level: float
    subgrid_level: float
    remarks: str = Field("", description="a hack for pandera")


class BasinTime(BaseModel):
    node_id: int
    time: datetime
    drainage: None | float = None
    potential_evaporation: None | float = None
    infiltration: None | float = None
    precipitation: None | float = None
    urban_runoff: None | float = None
    remarks: str = Field("", description="a hack for pandera")


class DiscreteControlCondition(BaseModel):
    node_id: int
    listen_feature_id: int
    variable: str
    greater_than: float
    look_ahead: None | float = None
    remarks: str = Field("", description="a hack for pandera")


class DiscreteControlLogic(BaseModel):
    node_id: int
    truth_state: str
    control_state: str
    remarks: str = Field("", description="a hack for pandera")


class Edge(BaseModel):
    fid: int
    name: str
    from_node_id: int
    to_node_id: int
    edge_type: str
    allocation_network_id: None | int = None
    remarks: str = Field("", description="a hack for pandera")


class FlowBoundaryStatic(BaseModel):
    node_id: int
    active: None | bool = None
    flow_rate: float
    remarks: str = Field("", description="a hack for pandera")


class FlowBoundaryTime(BaseModel):
    node_id: int
    time: datetime
    flow_rate: float
    remarks: str = Field("", description="a hack for pandera")


class FractionalFlowStatic(BaseModel):
    node_id: int
    fraction: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class LevelBoundaryStatic(BaseModel):
    node_id: int
    active: None | bool = None
    level: float
    remarks: str = Field("", description="a hack for pandera")


class LevelBoundaryTime(BaseModel):
    node_id: int
    time: datetime
    level: float
    remarks: str = Field("", description="a hack for pandera")


class LinearResistanceStatic(BaseModel):
    node_id: int
    active: None | bool = None
    resistance: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class ManningResistanceStatic(BaseModel):
    node_id: int
    active: None | bool = None
    length: float
    manning_n: float
    profile_width: float
    profile_slope: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class Node(BaseModel):
    fid: int
    name: str
    type: str
    allocation_network_id: None | int = None
    remarks: str = Field("", description="a hack for pandera")


class OutletStatic(BaseModel):
    node_id: int
    active: None | bool = None
    flow_rate: float
    min_flow_rate: None | float = None
    max_flow_rate: None | float = None
    min_crest_level: None | float = None
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class PidControlStatic(BaseModel):
    node_id: int
    active: None | bool = None
    listen_node_id: int
    target: float
    proportional: float
    integral: float
    derivative: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class PidControlTime(BaseModel):
    node_id: int
    listen_node_id: int
    time: datetime
    target: float
    proportional: float
    integral: float
    derivative: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class PumpStatic(BaseModel):
    node_id: int
    active: None | bool = None
    flow_rate: float
    min_flow_rate: None | float = None
    max_flow_rate: None | float = None
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class TabulatedRatingCurveStatic(BaseModel):
    node_id: int
    active: None | bool = None
    level: float
    flow_rate: float
    control_state: None | str = None
    remarks: str = Field("", description="a hack for pandera")


class TabulatedRatingCurveTime(BaseModel):
    node_id: int
    time: datetime
    level: float
    flow_rate: float
    remarks: str = Field("", description="a hack for pandera")


class TerminalStatic(BaseModel):
    node_id: int
    remarks: str = Field("", description="a hack for pandera")


class UserStatic(BaseModel):
    node_id: int
    active: None | bool = None
    demand: float
    return_factor: float
    min_level: float
    priority: int
    remarks: str = Field("", description="a hack for pandera")


class UserTime(BaseModel):
    node_id: int
    time: datetime
    demand: float
    return_factor: float
    min_level: float
    priority: int
    remarks: str = Field("", description="a hack for pandera")
