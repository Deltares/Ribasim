import os
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace

import networkx as nx
import numpy as np
import pytest
import xarray as xr
from ribasim import Model
from ribasim.delwaq import add_tracer, generate, parse, run_delwaq

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

    model = Model.read(toml_path)

    # With evaporation of mass disabled
    model.solver.evaporate_mass = False
    graph, substances = generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, graph, substances, model_dir, to_input=True)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == [
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

    model.write(tmp_path / "basic/ribasim.toml")


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

    graph, substances = generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, graph, substances, model_dir, to_input=True)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == [
        "Bar",
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


def test_delwaq_parse_concentration_dim_order(monkeypatch, tmp_path, basic):
    import importlib

    parse_mod = importlib.import_module("ribasim.delwaq.parse")

    toml_path = tmp_path / "model" / "ribasim.toml"
    basic.write(toml_path)

    results_dir = toml_path.parent / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    for required in ("basin_state.nc", "basin.nc", "flow.nc"):
        (results_dir / required).touch()

    # Minimal graph with two nodes so the parser can attach concentrations
    graph = nx.Graph()
    graph.add_node(1, id=101)
    graph.add_node(2, id=102)

    # Fake DELWAQ dataset with two substances (Foo and Continuity)
    times = np.array([0.0, 1.0], dtype=np.float32)
    nodes = np.array([0, 1], dtype=np.int32)
    coords = {
        "ribasim_nNodes": nodes,
        "nTimesDlwq": times,
        "ribasim_node_x": ("ribasim_nNodes", np.zeros_like(nodes, dtype=np.float32)),
        "ribasim_node_y": ("ribasim_nNodes", np.zeros_like(nodes, dtype=np.float32)),
    }
    data = xr.DataArray(
        np.ones((nodes.size, times.size), dtype=np.float32),
        dims=("ribasim_nNodes", "nTimesDlwq"),
        coords=coords,
        name="ribasim_Foo",
    )
    continuity = xr.DataArray(
        np.ones((nodes.size, times.size), dtype=np.float32),
        dims=("ribasim_nNodes", "nTimesDlwq"),
        coords=coords,
        name="ribasim_Continuity",
    )
    ds = xr.Dataset({"ribasim_Foo": data, "ribasim_Continuity": continuity})

    # Monkeypatch the xarray loader so parse() reads our in-memory dataset
    def fake_open_dataset(_):
        return nullcontext(ds)

    monkeypatch.setattr(
        parse_mod, "xu", SimpleNamespace(open_dataset=fake_open_dataset)
    )

    output_folder = tmp_path / "delwaq"
    output_folder.mkdir(parents=True, exist_ok=True)

    parse_mod.parse(basic, graph, {"Foo"}, output_folder=output_folder)

    # Ensure concentration.nc uses the expected dimension order
    with xr.open_dataset(results_dir / "concentration.nc") as uds:
        assert uds["concentration"].dims == ("node_id", "substance", "time")


@pytest.mark.parametrize(
    "name", ["Foo;123", "π", "AVeryLongSubstanceName", 'Double"Quote']
)
def test_invalid_substance_name(basic, name):
    with pytest.raises(ValueError, match="Invalid Delwaq substance"):
        add_tracer(basic, 11, name)
