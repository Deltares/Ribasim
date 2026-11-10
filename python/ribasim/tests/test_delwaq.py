import os
import re
from pathlib import Path

import numpy as np
import pytest
import xarray as xr
from ribasim import Model
from ribasim.delwaq import add_tracer, generate, parse, run_delwaq
from ribasim.delwaq.generate import _pass_down_term_flows, _setup_graph
from ribasim.delwaq.util import check_substance_uniqueness

delwaq_dir = Path(__file__).parent


@pytest.mark.skipif(
    not (
        ("D3D_HOME" in os.environ)
        and (
            delwaq_dir.parents[2] / "generated_testmodels/basic/results/flow.nc"
        ).is_file()
    ),
    reason="Requires Delwaq to be installed and basic model results.",
)
def test_offline_delwaq_coupling(tmp_path):
    repo_dir = delwaq_dir.parents[2]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"
    model_dir = tmp_path / "delwaq"
    results_dir = toml_path.parent / "results"

    model = Model.read(toml_path)

    # With evaporation of mass disabled
    model.solver.evaporate_mass = False
    generate(model, model_dir)

    # All files included by delwaq.inp are generated
    inp = (model_dir / "delwaq.inp").read_text()
    includes = re.findall(r"^INCLUDE '(.+?)'", inp, flags=re.MULTILINE)
    assert "include/B1_substances.inc" in includes
    for include in includes:
        assert (model_dir / include).is_file(), include

    run_delwaq(model_dir)
    model = parse(model, model_dir, to_input=True)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == [
        "Basic",
        "Cl",
        "Continuity",
        "Drainage",
        "FlowBoundary",
        "Initial",
        "LevelBoundary",
        "Precipitation",
        "SurfaceRunoff",
        "Tracer",
        "UserDemand",
    ]

    assert all(df[df.substance == "Continuity"].concentration >= 1.0 - 1e-6)
    assert all(np.isclose(df[df.substance == "UserDemand"].concentration, 0.0))
    assert any(
        df[df.substance == "Basic"].concentration > 0
    )  # MassLoad should be positive
    for _, node_load in df.groupby("node_id"):
        assert all(
            node_load[node_load.substance == "Basic"].concentration.diff()[1:] > -0.01
        )  # MassLoad should be (mostly) increasing over time

    model.write(tmp_path / "basic/ribasim.toml")

    # Ensure concentration.nc uses the expected dimension order
    with xr.open_dataset(results_dir / "concentration.nc") as uds:
        assert uds["concentration"].dims == ("time", "substance", "node_id")


@pytest.mark.skipif(
    not (
        ("D3D_HOME" in os.environ)
        and (
            delwaq_dir.parents[2] / "generated_testmodels/basic/results/flow.nc"
        ).is_file()
    ),
    reason="Requires Delwaq to be installed and basic model results.",
)
def test_offline_delwaq_coupling_evaporate_mass(tmp_path):
    repo_dir = delwaq_dir.parents[2]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"
    model_dir = tmp_path / "delwaq"

    model = Model.read(toml_path)

    # With evaporation of mass enabled
    model.solver.evaporate_mass = True
    add_tracer(model, 11, "Foo")
    add_tracer(model, 15, "Bar")
    add_tracer(model, 15, "Terrible' &%20Name")

    generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, model_dir, to_input=True)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == [
        "Bar",
        "Basic",
        "Cl",
        "Continuity",
        "Drainage",
        "FlowBoundary",
        "Foo",
        "Initial",
        "LevelBoundary",
        "Precipitation",
        "SurfaceRunoff",
        "Terrible' &%20Name",
        "Tracer",
        "UserDemand",
    ]

    assert all(np.isclose(df[df.substance == "Continuity"].concentration, 1.0))
    assert all(np.isclose(df[df.substance == "UserDemand"].concentration, 0.0))

    model.write(tmp_path / "basic/ribasim.toml")


@pytest.mark.parametrize("name", ["Foo;123", "π", 'Double"Quote'])
def test_invalid_substance_name(basic, name):
    with pytest.raises(ValueError, match="Invalid Delwaq substance"):
        add_tracer(basic, 11, name)


def test_substance_uniqueness():
    """Long names are allowed, but must be unique when truncated to 20 chars."""
    substances = {"AVeryLongSubstanceName"}
    check_substance_uniqueness(substances)

    substances = {"AVeryLongSubstanceNameAlpha", "AVeryLongSubstanceNameBeta"}
    with pytest.raises(ValueError, match="not unique when truncated"):
        check_substance_uniqueness(substances)


pass_down_results = (
    delwaq_dir.parents[2] / "generated_testmodels/pass_down_tracer/results/flow.nc"
)


@pytest.mark.skipif(
    not pass_down_results.is_file(),
    reason="Requires pass_down_tracer model results.",
)
def test_pass_down_network():
    """PassDown nodes are removed from the Delwaq network, with exchange flows per source."""
    toml_path = (
        delwaq_dir.parents[2] / "generated_testmodels/pass_down_tracer/ribasim.toml"
    )
    model = Model.read(toml_path)
    G, _merge_links, node_mapping, _link_mapping, _basin_mapping = _setup_graph(
        model.node, model.link, evaporate_mass=model.solver.evaporate_mass
    )
    assert all(d["type"] != "PassDown" for _, d in G.nodes(data=True))

    flows = xr.open_dataset(pass_down_results)["flow_rate"].to_dataframe().reset_index()
    flows["time"] = (
        (flows["time"] - flows["time"].iloc[0]).dt.total_seconds().astype("int32")
    )
    term_flows = _pass_down_term_flows(G, flows)
    assert term_flows is not None
    edges = list(G.edges())

    # FlowBoundary #1 (0.04 m³/s) and #2 (0.02 m³/s) mix in PassDown #3, of which 0.05 m³/s
    # flows on to Basin #7, so each FlowBoundary delivers its share of that
    for node_id, expected in ((1, 0.04 * 0.05 / 0.06), (2, 0.02 * 0.05 / 0.06)):
        i = edges.index((node_mapping[node_id], node_mapping[7]))
        flow = term_flows.loc[term_flows.link_id == i, "flow_rate"]
        assert len(flow) > 0
        assert np.allclose(flow, expected, rtol=1e-6)
