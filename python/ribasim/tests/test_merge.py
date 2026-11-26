"""Tests for merging Ribasim models."""

from datetime import datetime

import pandas as pd
import pytest
import ribasim
from pyproj import CRS
from ribasim.geometry.node import Node
from ribasim.merge import (
    _BOUNDARY_NODE_TYPES,
    ManningParameters,
    _concat_models,
    _find_boundary_pairs,
    _join_boundary_pair,
    _merge_models,
    _validate_descending_basin_profiles,
    merge_models,
)
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    manning_resistance,
    outlet,
)
from ribasim_testmodels import basic_model, river_model, tabulated_rating_curve_model
from shapely import Point


@pytest.fixture
def manning_parameters() -> ManningParameters:
    """Parameters for the ManningResistance nodes that replace joined boundaries."""
    return ManningParameters(
        length=1.0, manning_n=0.03, profile_width=1.0, profile_slope=0.01
    )


def test_merge_models_side_by_side(tmp_path):
    components = [basic_model(), tabulated_rating_curve_model()]
    model = ribasim.Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )
    model = _merge_models(components, model, id_offset=1000, x_offset=100.0)

    n_nodes = [len(c.node.df) for c in components]
    assert len(model.node.df) == sum(n_nodes)
    assert len(model.link.df) == sum(len(c.link.df) for c in components)
    assert model.node.df.index.is_unique
    assert (model.node.df.index[n_nodes[0] :] >= 1000).all()
    assert (model.link.df.from_node_id.isin(model.node.df.index)).all()
    assert (model.link.df.to_node_id.isin(model.node.df.index)).all()
    assert model.basin.static.df.node_id.isin(model.node.df.index).all()
    # The second component is translated
    shifted = components[1].node.df.geometry.x.to_numpy() + 100.0
    assert (model.node.df.geometry.x.to_numpy()[n_nodes[0] :] == shifted).all()

    model.write(tmp_path / "merged/ribasim.toml")
    ribasim.Model.read(tmp_path / "merged/ribasim.toml")


def test_concat_unique_ids():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4], first_id=1)

    merged, offset = _concat_models(a, b)

    assert merged.node.df.index.is_unique
    assert len(merged.node.df) == len(a.node.df) + len(b.node.df)
    assert offset == a.node.df.index.max()
    assert len(merged.basin.profile.df) == len(a.basin.profile.df) + len(
        b.basin.profile.df
    )
    assert len(merged.basin.node.df) == 4
    assert len(merged.manning_resistance.static.df) == 2
    assert sorted(merged.basin.node.df.index) == [1, 2, 4, 5]


def test_concat_links_reference_existing_nodes():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4])

    merged, _ = _concat_models(a, b)

    link = merged.link.df
    assert link.index.is_unique
    assert len(link) == len(a.link.df) + len(b.link.df)
    assert link["from_node_id"].isin(merged.node.df.index).all()
    assert link["to_node_id"].isin(merged.node.df.index).all()


def test_concat_does_not_change_inputs():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4])
    counts = (len(a.node.df), len(a.link.df), len(b.node.df), len(b.link.df))

    _concat_models(a, b)

    assert (len(a.node.df), len(a.link.df), len(b.node.df), len(b.link.df)) == counts
    assert b.node.df.index.min() == 1
    assert list(b.link.df.index) == [1, 2]
    assert list(b.basin.node.df.index) == [1, 2]


def test_concat_keeps_geometry():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4], x0=5000.0)

    merged, offset = _concat_models(a, b)

    shifted = merged.node.df.loc[b.node.df.index + offset]
    assert all(
        s.equals(o)
        for s, o in zip(shifted.geometry.values, b.node.df.geometry.values, strict=True)
    )
    assert shifted["node_type"].tolist() == b.node.df["node_type"].tolist()


def test_concat_renumbers_subnetwork_ids():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4])
    a.node.df["subnetwork_id"] = 1
    b.node.df["subnetwork_id"] = 1

    merged, offset = _concat_models(a, b)

    ids = merged.node.df["subnetwork_id"]
    assert (ids.loc[a.node.df.index] == 1).all()
    assert (ids.loc[b.node.df.index + offset] == 2).all()


def test_concat_write_read_roundtrip(tmp_path):
    a = river_model(bottoms=[10, 8], head=True)
    b = river_model(bottoms=[6, 4], tail=True)

    merged, _ = _concat_models(a, b)
    toml = tmp_path / "merged" / "ribasim.toml"
    merged.write(toml)
    read = ribasim.Model.read(toml)

    assert len(read.node.df) == len(merged.node.df)
    assert len(read.link.df) == len(merged.link.df)
    assert len(read.basin.profile.df) == 8
    assert a.filepath is None
    assert b.filepath is None


def test_concat_shifts_non_contiguous_ids():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4])
    b.basin.add(
        Node(10, b.node.df.geometry.iloc[0]),
        [basin.Profile(area=[1.0, 2.0], level=[3.0, 4.0])],
    )

    merged, offset = _concat_models(a, b)

    assert 10 + offset in merged.basin.node.df.index
    assert merged.basin.node.df.index.is_unique


def _boundary_id(model: ribasim.Model, node_type: str) -> int:
    df = model.node.df
    return int(df.index[df["node_type"] == node_type][0])


def test_find_pairs_matches_by_location():
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)

    pairs = _find_boundary_pairs(a, b)

    assert pairs == [
        (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary"))
    ]


def test_find_pairs_respects_tolerance():
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.5, head=True)

    assert _find_boundary_pairs(a, b) == []
    assert _find_boundary_pairs(a, b, tolerance=1.0) == [
        (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary"))
    ]


def test_find_pairs_ignores_non_boundary_nodes():
    a = river_model(bottoms=[10, 8], tail=True)
    # The first Basin of b lies at x=3000, on top of the LevelBoundary of a
    b = river_model(bottoms=[6, 4], x0=2000.0)

    assert _find_boundary_pairs(a, b) == []


def test_find_pairs_ambiguous_raises():
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    b.terminal.add(Node(10, Point(3000.0, 0)))

    with pytest.raises(ValueError, match="more than one"):
        _find_boundary_pairs(a, b)


def _add_level_listener(model: ribasim.Model, node_id: int, listen: int) -> None:
    model.discrete_control.add(
        Node(node_id, Point(2000.0, 500.0)),
        [
            discrete_control.Variable(
                listen_node_id=[listen], variable="level", compound_variable_id=1
            ),
            discrete_control.Condition(
                threshold_high=[0.5], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    model.link.add(model.level_boundary[listen], model.discrete_control[node_id])


def _rhine_hws():
    """Concatenate a river ending in a LevelBoundary with one starting at a FlowBoundary."""
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    merged, offset = _concat_models(a, b)
    pair = (
        _boundary_id(a, "LevelBoundary"),
        _boundary_id(b, "FlowBoundary") + offset,
    )
    return merged, pair, offset


def test_join_replaces_boundaries_and_connector(manning_parameters):
    merged, pair, offset = _rhine_hws()
    last_a = 2
    first_b = 2 + offset

    new_id = _join_boundary_pair(merged, *pair, manning=manning_parameters)

    types = merged.node.df["node_type"]
    assert not types.isin(["Terminal", "LevelBoundary", "FlowBoundary"]).any()
    assert "LinearResistance" not in set(types)
    assert merged.node.df.loc[new_id, "node_type"] == "ManningResistance"
    assert new_id in merged.manning_resistance.node.df.index
    link = merged.link.df
    assert (
        len(link[(link["from_node_id"] == last_a) & (link["to_node_id"] == new_id)])
        == 1
    )
    assert (
        len(link[(link["from_node_id"] == new_id) & (link["to_node_id"] == first_b)])
        == 1
    )


def test_join_accepts_pair_in_either_order(manning_parameters):
    merged, pair, offset = _rhine_hws()

    new_id = _join_boundary_pair(merged, pair[1], pair[0], manning=manning_parameters)

    link = merged.link.df
    assert ((link["from_node_id"] == 2) & (link["to_node_id"] == new_id)).any()
    assert ((link["from_node_id"] == new_id) & (link["to_node_id"] == 2 + offset)).any()


def test_join_manning_parameters_from_kwargs():
    merged, pair, _ = _rhine_hws()
    manning = ManningParameters(
        manning_n=0.05, length=2500.0, profile_width=60.0, profile_slope=1.0
    )
    new_id = _join_boundary_pair(merged, *pair, manning=manning)

    row = merged.manning_resistance.static.df.set_index("node_id").loc[new_id]
    assert row["manning_n"] == 0.05
    assert row["length"] == 2500.0
    assert row["profile_width"] == 60.0
    assert row["profile_slope"] == 1.0


def test_join_unknown_manning_parameter_raises():
    with pytest.raises(ValueError, match="roughness"):
        ManningParameters(roughness=1.0)


def test_join_same_side_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, tail=True)
    merged, offset = _concat_models(a, b)
    pair = (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "LevelBoundary") + offset)

    with pytest.raises(
        ValueError, match=rf"(?s)(?=.*\b{pair[0]}\b)(?=.*\b{pair[1]}\b)"
    ):
        _join_boundary_pair(merged, *pair, manning=manning_parameters)
    assert "LevelBoundary" in set(merged.node.df["node_type"])


def test_join_listener_repointed(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    level = _boundary_id(a, "LevelBoundary")
    _add_level_listener(a, 6, level)
    merged, offset = _concat_models(a, b)
    pair = (level, _boundary_id(b, "FlowBoundary") + offset)

    _join_boundary_pair(merged, *pair, manning=manning_parameters)

    assert merged.discrete_control.variable.df["listen_node_id"].tolist() == [2]
    link = merged.link.df
    listen = link[link["link_type"] == "listen"]
    assert listen[["from_node_id", "to_node_id"]].to_numpy().tolist() == [[2, 6]]


def test_join_listener_other_variable_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    flow = _boundary_id(b, "FlowBoundary")
    b.discrete_control.add(
        Node(10, Point(3000.0, 500.0)),
        [
            discrete_control.Variable(
                listen_node_id=[flow], variable="flow_rate", compound_variable_id=1
            ),
            discrete_control.Condition(
                threshold_high=[0.5], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    merged, offset = _concat_models(a, b)
    pair = (_boundary_id(a, "LevelBoundary"), flow + offset)

    with pytest.raises(ValueError, match="flow_rate"):
        _join_boundary_pair(merged, *pair, manning=manning_parameters)


def test_join_connector_with_control_link_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    linear = _boundary_id(a, "LinearResistance")
    a.discrete_control.add(
        Node(6, Point(2500.0, 500.0)),
        [
            discrete_control.Variable(
                listen_node_id=[1], variable="level", compound_variable_id=1
            ),
            discrete_control.Condition(
                threshold_high=[0.5], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    a.link.add(a.discrete_control[6], a.linear_resistance[linear])
    merged, offset = _concat_models(a, b)
    pair = (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary") + offset)

    with pytest.raises(ValueError, match=str(linear)):
        _join_boundary_pair(merged, *pair, manning=manning_parameters)


def test_join_boundary_with_two_flow_links_raises(manning_parameters):
    merged, pair, _offset = _rhine_hws()
    level = pair[0]
    merged.linear_resistance.add(
        Node(None, Point(3500.0, 500.0)),
        [linear_resistance.Static(resistance=[1.0])],
    )
    extra = int(merged.node.df.index.max())
    merged.link.add(merged.level_boundary[level], merged.linear_resistance[extra])
    merged.link.add(merged.linear_resistance[extra], merged.basin[2])

    with pytest.raises(ValueError, match="exactly one flow link"):
        _join_boundary_pair(merged, *pair, manning=manning_parameters)


def test_join_result_has_no_dangling_links(manning_parameters):
    merged, pair, _ = _rhine_hws()

    _join_boundary_pair(merged, *pair, manning=manning_parameters)

    link = merged.link.df
    assert link["from_node_id"].isin(merged.node.df.index).all()
    assert link["to_node_id"].isin(merged.node.df.index).all()
    assert len(link) == 4 + 2


def test_join_write_read_roundtrip(tmp_path, manning_parameters):
    merged, pair, _ = _rhine_hws()
    _join_boundary_pair(merged, *pair, manning=manning_parameters)

    toml = tmp_path / "joined" / "ribasim.toml"
    merged.write(toml)
    read = ribasim.Model.read(toml)

    assert len(read.node.df) == len(merged.node.df)
    assert len(read.link.df) == len(merged.link.df)


def test_merge_models_end_to_end(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)

    merged = merge_models(a, b, manning=manning_parameters)

    types = merged.node.df["node_type"]
    assert not types.isin(_BOUNDARY_NODE_TYPES).any()
    assert len(merged.manning_resistance.node.df) == (
        len(a.manning_resistance.node.df) + len(b.manning_resistance.node.df) + 1
    )
    assert len(merged.basin.node.df) == 4
    _validate_descending_basin_profiles(merged)


def test_merge_models_uses_first_boundary_location_and_warns_when_locations_differ(
    manning_parameters, caplog
):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3500.0, head=True)
    a_boundary = _boundary_id(a, "LevelBoundary")
    b_boundary = _boundary_id(b, "FlowBoundary")
    first_boundary_location = a.node.df.loc[a_boundary, "geometry"]

    with caplog.at_level("WARNING"):
        merged = merge_models(
            a,
            b,
            pairs=[(a_boundary, b_boundary)],
            manning=manning_parameters,
        )

    new_node = merged.node.df.loc[
        merged.node.df["meta_merged"].fillna(False).astype(bool)
    ].iloc[0]
    assert new_node.geometry == first_boundary_location
    assert "Boundary nodes" in caplog.text
    assert "exceeding the tolerance" in caplog.text
    assert "tolerance of 1e-06 m" in caplog.text


def test_merge_models_does_not_warn_when_boundary_locations_are_within_tolerance(
    manning_parameters, caplog
):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    boundary_id = _boundary_id(b, "FlowBoundary")
    b.node.df.loc[boundary_id, "geometry"] = Point(3000.5, 0)

    with caplog.at_level("WARNING"):
        merge_models(a, b, manning=manning_parameters, tolerance=1.0)

    assert "different locations" not in caplog.text


def test_merge_models_explicit_pairs_skip_matching(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3500.0, head=True)
    assert _find_boundary_pairs(a, b) == []

    merged = merge_models(
        a,
        b,
        pairs=[(_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary"))],
        manning=manning_parameters,
    )

    assert not merged.node.df["node_type"].isin(_BOUNDARY_NODE_TYPES).any()
    assert len(merged.basin.node.df) == 4


def test_merge_models_several_pairs_in_sequence(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    # A second connection: a LevelBoundary below the first Basin of a to a FlowBoundary
    # above the last Basin of b
    resistance = a.linear_resistance.add(
        Node(20, Point(1000.0, 250.0)), [linear_resistance.Static(resistance=[1.0])]
    )
    terminal = a.level_boundary.add(
        Node(21, Point(1000.0, 500.0)), [level_boundary.Static(level=[8.0])]
    )
    a.link.add(a.basin[1], resistance)
    a.link.add(resistance, terminal)
    flow = b.flow_boundary.add(
        Node(20, Point(1000.0, 500.0)), [flow_boundary.Static(flow_rate=[1.0])]
    )
    b.link.add(flow, b.basin[2])

    merged = merge_models(a, b, manning=manning_parameters)

    assert not merged.node.df["node_type"].isin(_BOUNDARY_NODE_TYPES).any()
    assert len(merged.basin.node.df) == 4
    assert len(merged.manning_resistance.node.df) == 4
    link = merged.link.df
    assert link["from_node_id"].isin(merged.node.df.index).all()
    assert link["to_node_id"].isin(merged.node.df.index).all()
    assert len(link) == 8
    assert not merged.node.df["node_type"].isin(["LinearResistance"]).any()


def test_merge_models_no_overlap_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3500.0, head=True)

    with pytest.raises(ValueError, match="No overlapping boundary"):
        merge_models(a, b, manning=manning_parameters)


def test_merge_models_unknown_pair_node_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)

    with pytest.raises(ValueError, match="does not exist"):
        merge_models(a, b, pairs=[(99, 1)], manning=manning_parameters)


def test_merge_models_crs_mismatch_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True, crs="EPSG:4326")

    with pytest.raises(ValueError, match="CRS"):
        merge_models(a, b, manning=manning_parameters)


def test_merge_models_time_mismatch_warns_and_keeps_first(manning_parameters, caplog):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(
        bottoms=[6, 4],
        x0=3000.0,
        head=True,
        starttime=datetime(2019, 1, 1),
        endtime=datetime(2022, 1, 1),
    )

    with caplog.at_level("WARNING"):
        merged = merge_models(a, b, manning=manning_parameters)

    assert "different starttime" in caplog.text
    assert "different endtime" in caplog.text
    assert merged.starttime == a.starttime
    assert merged.endtime == a.endtime


def test_merge_models_ascending_result_raises(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[9, 4], x0=3000.0, head=True)

    with pytest.raises(ValueError, match="must not rise"):
        merge_models(a, b, manning=manning_parameters)


def test_merge_models_does_not_change_inputs(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    before = [df.copy() for df in (a.node.df, a.link.df, b.node.df, b.link.df)]

    merge_models(a, b, manning=manning_parameters)

    for expected, actual in zip(
        before, (a.node.df, a.link.df, b.node.df, b.link.df), strict=True
    ):
        pd.testing.assert_frame_equal(expected, actual)


def _basin_ids(model) -> list[int]:
    return model.basin.node.df.index.tolist()


def test_descending_profiles_pass():
    model = river_model(bottoms=[10, 8, 6])
    _validate_descending_basin_profiles(model)


def test_equal_bottoms_pass():
    model = river_model(bottoms=[5, 5])
    _validate_descending_basin_profiles(model)


def test_ascending_profile_raises():
    model = river_model(bottoms=[5, 7])
    upstream, downstream = _basin_ids(model)
    with pytest.raises(ValueError, match=rf"{upstream}.*{downstream}"):
        _validate_descending_basin_profiles(model)


def test_path_through_pump_is_skipped():
    model = river_model(bottoms=[5, 7], head=True)
    upstream, downstream = _basin_ids(model)
    manning_id = model.manning_resistance.node.df.index[0]
    model.remove_node(int(manning_id))

    gate = model.outlet.add(
        Node(manning_id, Point(1500, 0)), [outlet.Static(flow_rate=[1.0])]
    )
    model.link.add(model.basin[upstream], gate)
    model.link.add(gate, model.basin[downstream])

    _validate_descending_basin_profiles(model)


def test_confluence_checks_every_upstream_basin():
    model = river_model(bottoms=[10, 5])
    _, downstream = _basin_ids(model)
    side = model.basin.add(
        Node(10, Point(1000, 500)),
        [
            basin.Profile(area=[100.0, 200.0], level=[3.0, 4.0]),
            basin.Static(surface_runoff=[0.0]),
            basin.State(level=[3.0]),
        ],
    )
    side_manning = model.manning_resistance.add(
        Node(11, Point(1500, 250)),
        [
            manning_resistance.Static(
                length=[1000.0],
                manning_n=[0.03],
                profile_width=[50.0],
                profile_slope=[1.0],
            )
        ],
    )
    model.link.add(side, side_manning)
    model.link.add(side_manning, model.basin[downstream])

    # the main upstream basin (10) is fine, only the side basin (3) is too low
    with pytest.raises(ValueError, match=rf"10.*{downstream}"):
        _validate_descending_basin_profiles(model)


def test_manning_parameters_match_ribasim_schema():
    schema_columns = set(manning_resistance.Static.columns())
    ours = set(ManningParameters.model_fields)
    assert ours == schema_columns - {"node_id"}


def test_manning_parameters_allow_meta_keys():
    manning = ManningParameters(
        length=1.0,
        manning_n=0.03,
        profile_width=1.0,
        profile_slope=0.0,
        meta_source="merge",
    )

    static = manning.to_static().df
    assert static["meta_source"].iloc[0] == "merge"
    assert pd.isna(static["control_state"].iloc[0])


def test_manning_parameters_control_state():
    manning = ManningParameters(
        length=1.0,
        manning_n=0.03,
        profile_width=1.0,
        profile_slope=0.0,
        control_state="on",
    )

    assert manning.to_static().df["control_state"].iloc[0] == "on"


def test_merge_models_manning_meta_and_merged_flag(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    manning = ManningParameters(
        length=1.0, manning_n=0.03, profile_width=1.0, profile_slope=0.0, meta_x="a"
    )

    merged = merge_models(a, b, manning=manning)

    new = merged.node.df[merged.node.df["meta_merged"].fillna(False).astype(bool)]
    assert list(new["node_type"]) == ["ManningResistance"]
    static = merged.manning_resistance.static.df.set_index("node_id")
    assert static.loc[new.index[0], "meta_x"] == "a"


def test_find_pairs_tolerance_is_in_meters():
    a = river_model(bottoms=[10, 8], tail=True, crs="EPSG:3857")
    b = river_model(bottoms=[6, 4], x0=3000.5, head=True, crs="EPSG:3857")

    # EPSG:3857 units are meters; the nodes are 0.5 m apart
    assert _find_boundary_pairs(a, b, tolerance=0.4) == []
    assert len(_find_boundary_pairs(a, b, tolerance=0.6)) == 1


def test_find_pairs_projected_feet_uses_meters():
    a = river_model(bottoms=[10, 8], tail=True, crs="EPSG:2263")
    b = river_model(bottoms=[6, 4], x0=3000.5, head=True, crs="EPSG:2263")

    assert _find_boundary_pairs(a, b, tolerance=0.15) == []
    assert _find_boundary_pairs(a, b, tolerance=0.16) == [
        (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary"))
    ]


@pytest.mark.parametrize(
    ("first", "second", "near", "far"),
    [
        ((4.0, 52.0), (4.00001, 52.0), 0.6, 0.8),
        ((0.0, 85.0), (0.0001, 85.0), 0.8, 1.1),
        ((179.99999, 0.0), (-179.99999, 0.0), 2.0, 2.4),
    ],
)
def test_find_pairs_geographic_crs_uses_meters(first, second, near, far):
    a = river_model(bottoms=[10, 8], tail=True, crs="EPSG:4326")
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True, crs="EPSG:4326")
    a_id = _boundary_id(a, "LevelBoundary")
    b_id = _boundary_id(b, "FlowBoundary")
    a.node.df.loc[a_id, "geometry"] = Point(*first)
    b.node.df.loc[b_id, "geometry"] = Point(*second)
    a_nodes = a.node.df.copy()
    b_nodes = b.node.df.copy()

    assert _find_boundary_pairs(a, b, tolerance=near) == []
    assert _find_boundary_pairs(a, b, tolerance=far) == [(a_id, b_id)]
    pd.testing.assert_frame_equal(a.node.df, a_nodes)
    pd.testing.assert_frame_equal(b.node.df, b_nodes)


def test_find_pairs_geographic_crs_does_not_construct_local_crs(monkeypatch):
    a = river_model(bottoms=[10, 8], tail=True, crs="EPSG:4326")
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True, crs="EPSG:4326")
    a_id = _boundary_id(a, "LevelBoundary")
    b_id = _boundary_id(b, "FlowBoundary")
    a.node.df.loc[a_id, "geometry"] = Point(4.0, 52.0)
    b.node.df.loc[b_id, "geometry"] = Point(4.00001, 52.0)

    def reject_local_crs(*args, **kwargs):
        pytest.fail("Boundary matching should not construct a local CRS.")

    monkeypatch.setattr(CRS, "from_proj4", reject_local_crs)

    assert _find_boundary_pairs(a, b, tolerance=0.8) == [(a_id, b_id)]


def test_merge_models_geographic_crs(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    for model in (a, b):
        model.node.df = model.node.df.to_crs("EPSG:4326")
        model.link.df = model.link.df.to_crs("EPSG:4326")
        model.crs = "EPSG:4326"
    original_basin = a.basin.node.df.geometry.loc[1]

    merged = merge_models(a, b, manning=manning_parameters)

    assert merged.crs == "EPSG:4326"
    assert merged.basin.node.df.geometry.loc[1] == original_basin
    assert len(merged.basin.node.df) == 4
    assert not merged.node.df["node_type"].isin(_BOUNDARY_NODE_TYPES).any()


def _set_authorities(model, boundary_type, authority, couple_authority):
    df = model.node.df
    df["meta_authority"] = authority
    df.loc[df["node_type"] == boundary_type, "meta_couple_authority"] = couple_authority
    model.node.df = df


def test_find_pairs_matches_authorities():
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    _set_authorities(a, "LevelBoundary", "A", "B")
    _set_authorities(b, "FlowBoundary", "B", "A")

    assert _find_boundary_pairs(a, b) == [
        (_boundary_id(a, "LevelBoundary"), _boundary_id(b, "FlowBoundary"))
    ]


def test_find_pairs_authority_mismatch_not_paired():
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    _set_authorities(a, "LevelBoundary", "A", "C")
    _set_authorities(b, "FlowBoundary", "B", "A")

    assert _find_boundary_pairs(a, b) == []


def test_concat_id_prefix():
    a = river_model(bottoms=[10, 8])
    b = river_model(bottoms=[6, 4])

    merged, offset = _concat_models(a, b, id_prefix=2)

    assert offset == 20
    assert sorted(merged.basin.node.df.index) == [1, 2, 21, 22]
    assert merged.node.df.index.is_unique
    link = merged.link.df
    assert link["from_node_id"].isin(merged.node.df.index).all()
    assert link["to_node_id"].isin(merged.node.df.index).all()


def test_concat_id_prefix_overlap_raises():
    a = river_model(bottoms=[10, 8], first_id=21)
    b = river_model(bottoms=[6, 4])

    with pytest.raises(ValueError, match="overlap"):
        _concat_models(a, b, id_prefix=2)


def test_merge_models_id_prefix(manning_parameters):
    a = river_model(bottoms=[10, 8], tail=True)
    b = river_model(bottoms=[6, 4], x0=3000.0, head=True)

    merged = merge_models(a, b, manning=manning_parameters, id_prefix=2)

    assert sorted(merged.basin.node.df.index) == [1, 2, 22, 23]
