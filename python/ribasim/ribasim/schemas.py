# Automatically generated file. Do not modify.

from typing import Annotated, Any, Callable

import pandas as pd
import pandera as pa
import pyarrow
from pandera.dtypes import Int32
from pandera.typing import Index, Series

from ribasim import migrations


class _BaseSchema(pa.DataFrameModel):
    class Config:
        add_missing_columns = True
        coerce = True

    @classmethod
    def _index_name(self) -> str:
        return "fid"

    @classmethod
    def migrate(cls, df: Any, schema_version: int) -> Any:
        f: Callable[[Any, Any], Any] = getattr(
            migrations, str(cls.__name__).lower() + "_migration", lambda x, _: x
        )
        return f(df, schema_version)


class BasinConcentrationExternalSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    substance: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    concentration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class BasinConcentrationStateSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    substance: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    concentration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class BasinConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    substance: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    drainage: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    precipitation: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class BasinProfileSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    area: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)


class BasinStateSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)


class BasinStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    drainage: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    potential_evaporation: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )
    infiltration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    precipitation: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class BasinSubgridSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    subgrid_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    basin_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    subgrid_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class BasinTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    drainage: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    potential_evaporation: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )
    infiltration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    precipitation: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class ContinuousControlFunctionSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    input: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)
    output: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    controlled_variable: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class ContinuousControlVariableSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    listen_node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    variable: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    weight: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    look_ahead: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class DiscreteControlConditionSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    compound_variable_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    greater_than: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class DiscreteControlLogicSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    truth_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class DiscreteControlVariableSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    compound_variable_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    listen_node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    variable: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    weight: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    look_ahead: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class FlowBoundaryConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    substance: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    concentration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class FlowBoundaryStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class FlowBoundaryTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class FlowDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    demand: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )


class FlowDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    demand: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )


class LevelBoundaryConcentrationSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    substance: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )
    concentration: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )


class LevelBoundaryStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)


class LevelBoundaryTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)


class LevelDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    min_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )


class LevelDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    min_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )


class LinearResistanceStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    resistance: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class ManningResistanceStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    length: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    manning_n: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    profile_width: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    profile_slope: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class OutletStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_upstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_downstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class PidControlStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    listen_node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    target: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    proportional: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    integral: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    derivative: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class PidControlTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    listen_node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    target: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    proportional: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    integral: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    derivative: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class PumpStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_upstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_downstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class TabulatedRatingCurveStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_downstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )
    control_state: Series[Annotated[pd.ArrowDtype, pyarrow.string()]] = pa.Field(
        nullable=True
    )


class TabulatedRatingCurveTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(nullable=True)
    flow_rate: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    max_downstream_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = (
        pa.Field(nullable=True)
    )


class UserDemandStaticSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    active: Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]] = pa.Field(nullable=True)
    demand: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    return_factor: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )


class UserDemandTimeSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=1, check_name=True, coerce=True)
    node_id: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(nullable=True)
    time: Series[Annotated[pd.ArrowDtype, pyarrow.timestamp("ms")]] = pa.Field(
        nullable=True
    )
    demand: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    return_factor: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    min_level: Series[Annotated[pd.ArrowDtype, pyarrow.float64()]] = pa.Field(
        nullable=True
    )
    priority: Series[Annotated[pd.ArrowDtype, pyarrow.int32()]] = pa.Field(
        nullable=True
    )
