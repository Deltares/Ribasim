from datetime import datetime

import numpy as np
from ribasim.config import Allocation, Experimental, Solver
from ribasim.geometry.node import Node
from ribasim.input_base import NodeData
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    junction,
    pump,
    tabulated_rating_curve,
    user_demand,
)
from shapely.geometry import Point


def invalid_qh_model() -> Model:
    """
    Invalid TabulatedRatingCurve Q(h) table.

    - flow_rate must start at 0
    - flow_rate must not be decreasing
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 12, 1),
        crs="EPSG:28992",
        use_validation=False,
    )

    bsn = model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.State(level=[1.0]),
            basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
        ],
    )

    trc = model.tabulated_rating_curve.add(
        Node(2, Point(1, 0)),
        [tabulated_rating_curve.Static(level=[0, 0.5, 1], flow_rate=[1, 2, 1.5])],
    )

    trm = model.terminal.add(Node(3, Point(3, 0)))

    model.link.add(bsn, trc)
    model.link.add(trc, trm)

    return model


def invalid_control_states_model() -> Model:
    """Pump with multiple control states, without DiscreteControl or a row without control_state."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 12, 1),
        crs="EPSG:28992",
        use_validation=False,
    )

    bsn = model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.State(level=[1.0]),
            basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
        ],
    )
    pmp = model.pump.add(
        Node(2, Point(1, 0)),
        [pump.Static(flow_rate=[0.0, 1e-3], control_state=["off", "on"])],
    )
    trm = model.terminal.add(Node(3, Point(2, 0)))

    model.link.add(bsn, pmp)
    model.link.add(pmp, trm)

    return model


def invalid_discrete_control_model() -> Model:
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 12, 1),
        crs="EPSG:28992",
        use_validation=False,
    )

    basin_shared = [
        basin.Profile(area=[0.01, 1.0], level=[0.0, 1.0]),
        basin.State(level=[1.4112729908597084]),
    ]
    model.basin.add(Node(1, Point(0, 0)), basin_shared)
    # Invalid: DiscreteControl node #4 with control state 'foo'
    # points to this pump but this control state is not defined for
    # this pump. The pump having a control state that is not defined
    # for DiscreteControl node #4 is fine.
    model.pump.add(
        Node(2, Point(1, 0)), [pump.Static(control_state="bar", flow_rate=[0.5 / 3600])]
    )
    model.basin.add(Node(3, Point(2, 0)), basin_shared)
    model.flow_boundary.add(
        Node(4, Point(3, 0)),
        [
            flow_boundary.Time(
                time=["2020-01-01", "2020-11-01"],
                flow_rate=[1.0, 2.0],
            )
        ],
    )
    model.discrete_control.add(
        Node(5, Point(1, 1)),
        [
            discrete_control.Variable(
                listen_node_id=[1, 4, 4],
                variable=["level", "flow_rate", "flow_rate"],
                # Invalid: look_ahead can only be specified for timeseries variables.
                # Invalid: this look_ahead will go past the provided timeseries during simulation.
                # Invalid: look_ahead must be non-negative.
                look_ahead=[100.0, 40 * 24 * 60 * 60, -10.0],
                compound_variable_id=[1, 2, 3],
            ),
            discrete_control.Condition(
                threshold_high=[0.5, 1.5, 1.5],
                compound_variable_id=[1, 2, 3],
                condition_id=1,
            ),
            # Invalid: DiscreteControl node #4 has 2 conditions so
            # truth states have to be of length 2
            discrete_control.Logic(truth_state=["FFFF"], control_state=["foo"]),
        ],
    )

    model.link.add(
        model.basin[1],
        model.pump[2],
    )
    model.link.add(
        model.pump[2],
        model.basin[3],
    )
    model.link.add(
        model.flow_boundary[4],
        model.basin[3],
    )
    model.link.add(
        model.discrete_control[5],
        model.pump[2],
    )

    return model


def invalid_link_types_model() -> Model:
    """Set up a minimal model with invalid link types."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 12, 1),
        crs="EPSG:28992",
        use_validation=False,
    )

    basin_shared = [
        basin.Profile(area=[0.01, 1000.0], level=[0.0, 1.0]),
        basin.State(level=[0.04471158417652035]),
    ]

    model.basin.add(Node(1, Point(0, 0)), basin_shared)
    model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.5 / 3600])])
    model.basin.add(Node(3, Point(2, 0)), basin_shared)

    model.link.add(
        model.basin[1],
        model.pump[2],
    )
    model.link.add(
        model.pump[2],
        model.basin[3],
    )

    model.link.df["link_type"] = ["foo", "bar"]

    return model


def invalid_unstable_model() -> Model:
    """Model with several extremely quickly emptying basins."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
        solver=Solver(dtmin=60.0),
        use_validation=False,
    )
    id_shift = 10
    for i in range(6):
        model.basin.add(
            Node(1 + id_shift * i, Point(i, 0)),
            [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
        )
        flow_rate = 1.0 if (i % 2 == 0) else 1e10
        model.pump.add(
            Node(2 + id_shift * i, Point(i, 1)),
            [pump.Static(flow_rate=[flow_rate])],
        )
        model.terminal.add(Node(3 + id_shift * i, Point(i, 2)))

        model.link.add(model.basin[1 + id_shift * i], model.pump[2 + id_shift * i])
        model.link.add(model.pump[2 + id_shift * i], model.terminal[3 + id_shift * i])
    return model


def invalid_no_basin_model() -> Model:
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )

    # Setup flow boundary
    boundary1 = model.flow_boundary.add(
        Node(1, Point(0.0, 0.0)), [flow_boundary.Static(flow_rate=[1e-4])]
    )
    # Setup another flow boundary
    boundary2 = model.flow_boundary.add(
        Node(2, Point(2.0, 0.0)), [flow_boundary.Static(flow_rate=[1e-4])]
    )

    # Setup terminal
    sea = model.terminal.add(Node(3, Point(1.0, -1.0)))

    model.link.add(boundary1, sea)
    model.link.add(boundary2, sea)

    return model


def _invalid_junction_base() -> tuple[Model, NodeData]:
    """Create a model with a Basin and a Pump, to which Junction nodes can be connected."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )
    bsn = model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.State(level=[1.0]),
            basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
        ],
    )
    pmp = model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[1e-3])])
    model.link.add(bsn, pmp)
    return model, pmp


def _junction_user_demand_static() -> list:
    return [
        user_demand.Static(
            demand_priority=[1], demand=[1e-4], return_factor=0.5, min_level=[0.0]
        )
    ]


def invalid_junction_missing_fractions_model() -> Model:
    """Divide the flow of a Junction over three Terminals with two missing fractions."""
    model, pmp = _invalid_junction_base()
    jct = model.junction.add(
        Node(7, Point(1.5, 0)),
        [junction.Static(to_node_id=[3, 4, 5], fraction=[np.nan, np.nan, 0.5])],
    )
    model.link.add(pmp, jct)
    for node_id, y in [(3, 1), (4, 0), (5, -1)]:
        trm = model.terminal.add(Node(node_id, Point(2, y)))
        model.link.add(jct, trm)
    return model


def invalid_junction_fraction_sum_model() -> Model:
    """Junction fractions summing to more than 1, while one fraction is missing."""
    model, pmp = _invalid_junction_base()
    jct = model.junction.add(
        Node(7, Point(1.5, 0)),
        [junction.Static(to_node_id=[3, 4, 5], fraction=[0.75, 0.5, np.nan])],
    )
    model.link.add(pmp, jct)
    for node_id, y in [(3, 1), (4, 0), (5, -1)]:
        trm = model.terminal.add(Node(node_id, Point(2, y)))
        model.link.add(jct, trm)
    return model


def invalid_junction_connector_split_model() -> Model:
    """Create a Pump that flows directly into two Junctions, instead of via a Junction that divides the flow."""
    model, pmp = _invalid_junction_base()
    trm = model.terminal.add(Node(6, Point(3, 0)))
    # Temporary Junction, since the link validation does not allow this connectivity
    jct_tmp = model.junction.add(Node(7, Point(1.5, 0)))
    jct1 = model.junction.add(
        Node(3, Point(2, 1)), [junction.Static(to_node_id=[6], fraction=[1.0])]
    )
    jct2 = model.junction.add(
        Node(4, Point(2, -1)), [junction.Static(to_node_id=[6], fraction=[1.0])]
    )
    model.link.add(pmp, jct1)
    model.link.add(jct_tmp, jct2)
    model.link.add(jct1, trm)
    model.link.add(jct2, trm)
    assert model.link.df is not None
    model.link.df.loc[
        model.link.df["from_node_id"] == jct_tmp.node_id, "from_node_id"
    ] = pmp.node_id
    model.remove_node(jct_tmp.node_id)
    return model


def invalid_junction_multiple_user_demands_model() -> Model:
    """Junction with multiple UserDemand nodes downstream."""
    model, pmp = _invalid_junction_base()
    jct = model.junction.add(
        Node(3, Point(2, 0)), [junction.Static(to_node_id=[6], fraction=[1.0])]
    )
    ud1 = model.user_demand.add(Node(4, Point(3, 1)), _junction_user_demand_static())
    ud2 = model.user_demand.add(Node(5, Point(3, -1)), _junction_user_demand_static())
    trm = model.terminal.add(Node(6, Point(4, 0)))
    model.link.add(pmp, jct)
    model.link.add(jct, ud1)
    model.link.add(jct, ud2)
    model.link.add(jct, trm)
    model.link.add(ud1, trm)
    model.link.add(ud2, trm)
    return model


def invalid_junction_only_user_demand_model() -> Model:
    """Junction with only a UserDemand node downstream, so the remaining flow has nowhere to go."""
    model, pmp = _invalid_junction_base()
    jct = model.junction.add(
        Node(3, Point(2, 0)), [junction.Static(to_node_id=[4], fraction=[1.0])]
    )
    ud = model.user_demand.add(Node(4, Point(3, 0)), _junction_user_demand_static())
    trm = model.terminal.add(Node(5, Point(4, 0)))
    model.link.add(pmp, jct)
    model.link.add(jct, ud)
    model.link.add(ud, trm)
    return model


def invalid_user_demand_missing_min_level_model() -> Model:
    """UserDemand abstracting from a Basin without a min_level."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )
    bsn = model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.State(level=[1.0]),
            basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
        ],
    )
    ud = model.user_demand.add(
        Node(2, Point(1, 0)),
        [user_demand.Static(demand_priority=[1], demand=[1e-4], return_factor=0.5)],
    )
    trm = model.terminal.add(Node(3, Point(2, 0)))
    model.link.add(bsn, ud)
    model.link.add(ud, trm)
    return model


def _invalid_subnetwork_model() -> Model:
    """Create an empty model with allocation, to connect the primary network and subnetworks in."""
    return Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
        allocation=Allocation(),
        experimental=Experimental(allocation=True),
    )


def _invalid_subnetwork_basin_tables() -> list:
    return [
        basin.State(level=[1.0]),
        basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
    ]


def invalid_junction_subnetwork_boundary_model() -> Model:
    """Put a Junction that stays in the simulation at the boundary between the primary network and a subnetwork."""
    model = _invalid_subnetwork_model()
    bsn1 = model.basin.add(Node(1, Point(0, 0)), _invalid_subnetwork_basin_tables())
    pmp = model.pump.add(
        Node(2, Point(1, 0)),
        [pump.Static(flow_rate=[1e-3], allocation_controlled=[True])],
    )
    jct = model.junction.add(
        Node(3, Point(2, 0), subnetwork_id=2),
        [junction.Static(to_node_id=[4], fraction=[1.0])],
    )
    bsn2 = model.basin.add(
        Node(4, Point(3, 0), subnetwork_id=2), _invalid_subnetwork_basin_tables()
    )
    model.link.add(bsn1, pmp)
    model.link.add(pmp, jct)
    model.link.add(jct, bsn2)
    return model


def invalid_junction_no_basin_allocation_model() -> Model:
    """Allocation subnetwork without a Basin, which allocation does not support."""
    from ribasim_testmodels.junction import _junction_chain

    model = _invalid_subnetwork_model()
    _junction_chain(model, 2)
    return model


def invalid_subnetwork_to_primary_model() -> Model:
    """Flow from a subnetwork into the primary network."""
    model = _invalid_subnetwork_model()
    bsn1 = model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=2), _invalid_subnetwork_basin_tables()
    )
    pmp = model.pump.add(
        Node(2, Point(1, 0), subnetwork_id=2), [pump.Static(flow_rate=[1e-3])]
    )
    bsn2 = model.basin.add(Node(3, Point(2, 0)), _invalid_subnetwork_basin_tables())
    model.link.add(bsn1, pmp)
    model.link.add(pmp, bsn2)
    return model
