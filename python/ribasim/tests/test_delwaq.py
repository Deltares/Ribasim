import os
import re
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import ribasim
import xarray as xr
from ribasim import Model
from ribasim.delwaq import add_tracer, generate, parse, run_delwaq
from ribasim.delwaq.generate import _junction_term_flows, _setup_graph
from ribasim.delwaq.util import check_substance_uniqueness
from ribasim_testmodels import junction_bidirectional

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
    # Copy the model, since parse overwrites the results
    shutil.copytree(repo_dir / "generated_testmodels/basic", tmp_path / "model")
    toml_path = tmp_path / "model/ribasim.toml"
    model_dir = tmp_path / "delwaq"
    results_dir = toml_path.parent / "results"

    model = Model.read(toml_path)
    core = xr.load_dataset(results_dir / "concentration.nc")

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
    ]

    assert all(df[df.substance == "Continuity"].concentration >= 1.0 - 1e-6)
    assert any(
        df[df.substance == "Basic"].concentration > 0
    )  # MassLoad should be positive
    for _, node_load in df.groupby("node_id"):
        assert all(
            node_load[node_load.substance == "Basic"].concentration.diff()[1:] > -0.01
        )  # MassLoad should be (mostly) increasing over time

    model.write(tmp_path / "basic/ribasim.toml")

    # parse writes concentration.nc like the core, with the records at the same times
    delwaq = xr.load_dataset(results_dir / "concentration.nc")
    assert delwaq["concentration"].dims == ("time", "substance", "node_id")
    assert delwaq.attrs.keys() == core.attrs.keys()
    for name in ("time", "node_id", "concentration"):
        assert delwaq[name].dtype == core[name].dtype
    # The dtype of strings includes the length of the longest
    assert delwaq.substance.dtype.kind == core.substance.dtype.kind
    for name in ("time", "node_id", "substance", "concentration"):
        assert delwaq[name].attrs == core[name].attrs
    assert (delwaq.time == core.time).all()
    assert (delwaq.node_id == core.node_id).all()
    # Delwaq has all tracers of the core except ResidenceTime
    assert set(delwaq.substance.to_numpy()) == set(core.substance.to_numpy()) - {
        "ResidenceTime"
    }
    # Both start with the initial condition
    initial = delwaq.concentration.sel(substance="Initial").isel(time=0)
    assert np.allclose(initial, 1.0)
    assert np.allclose(core.concentration.sel(substance="Initial").isel(time=0), 1.0)


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
    # Copy the model, since parse overwrites the results
    shutil.copytree(repo_dir / "generated_testmodels/basic", tmp_path / "model")
    toml_path = tmp_path / "model/ribasim.toml"
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
    ]

    assert all(np.isclose(df[df.substance == "Continuity"].concentration, 1.0))

    model.write(tmp_path / "basic/ribasim.toml")


@pytest.mark.skipif(
    not (
        ("D3D_HOME" in os.environ)
        and (
            delwaq_dir.parents[2]
            / "generated_testmodels/tracer_user_demand/results/flow.nc"
        ).is_file()
    ),
    reason="Requires Delwaq to be installed and tracer_user_demand model results.",
)
def test_offline_delwaq_coupling_user_demand(tmp_path):
    """UserDemand return flows carry the concentrations of the abstracted water."""
    repo_dir = delwaq_dir.parents[2]
    # Copy the model, since parse overwrites the results
    shutil.copytree(
        repo_dir / "generated_testmodels/tracer_user_demand", tmp_path / "model"
    )
    model = Model.read(tmp_path / "model/ribasim.toml")
    model_dir = tmp_path / "delwaq"

    generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, model_dir, to_input=True)

    df = model.basin.concentration_external.df
    assert df is not None
    df = df.pivot_table(
        index=["time", "node_id"], columns="substance", values="concentration"
    )
    assert np.allclose(df["Continuity"], 1.0)
    # Without the return flows, a UserDemand would be a source of water in Basin #6
    assert np.allclose(df["FlowBoundary"] + df["Initial"], 1.0)


def test_parse_without_delwaq(basic, tmp_path):
    """Parse maps the Delwaq segments back to Basins and writes them like the core."""
    toml_path = tmp_path / "basic/ribasim.toml"
    basic.write(toml_path)
    results_dir = toml_path.parent / "results"
    results_dir.mkdir()
    for name in ("basin_state.nc", "basin.nc", "flow.nc"):
        (results_dir / name).touch()

    # Delwaq output with the segments in another order than the Basins
    folder = tmp_path / "delwaq"
    folder.mkdir()
    segment_node_id = [9, 3, 1, 6]
    substances = sorted(
        [
            "Continuity",
            "Initial",
            "LevelBoundary",
            "FlowBoundary",
            "Drainage",
            "Precipitation",
            "SurfaceRunoff",
            "Basic",
            "Cl",
            "Tracer",
        ]
    )
    xr.Dataset(
        {
            "ribasim_node_id": ("ribasim_nNodes", segment_node_id),
            "substances": ("substance", substances),
        },
        coords={"node_id": ("ribasim_nNodes", [1, 2, 3, 4])},
    ).to_netcdf(folder / "ribasim.nc")
    time = pd.date_range("2020-01-01", periods=3, freq="D")

    def value(substance: str, node_id, t) -> np.ndarray:
        return 100.0 * substances.index(substance) + 10.0 * node_id + t

    t, node_id = np.meshgrid(np.arange(3), segment_node_id, indexing="ij")
    xr.Dataset(
        {
            f"ribasim_{substance}": (
                ("nTimesDlwq", "ribasim_nNodes"),
                value(substance, node_id, t).astype(np.float32),
            )
            for substance in substances
        },
        coords={"nTimesDlwq": time},
    ).to_netcdf(folder / "delwaq_map.nc")

    model = parse(toml_path, folder, to_input=True)

    with xr.open_dataset(results_dir / "concentration.nc") as ds:
        assert ds.attrs == {
            "Conventions": "CF-1.12",
            "references": "https://ribasim.org",
            "ribasim_version": ribasim.__version__,
            "title": "Ribasim results: concentration",
        }
        assert ds["concentration"].dims == ("time", "substance", "node_id")
        assert ds["concentration"].dtype == np.float64
        assert ds["concentration"].attrs["units"] == "g m-3"
        encoding = ds["concentration"].encoding
        assert encoding["zlib"]
        assert encoding["shuffle"]
        assert encoding["chunksizes"] == (3, 1, 4)
        assert ds["node_id"].dtype == np.int32
        assert list(ds.node_id.to_numpy()) == [1, 3, 6, 9]
        assert (ds.time.to_numpy() == time.to_numpy()).all()
        assert list(ds.substance.to_numpy()) == substances
        for substance in substances:
            expected = value(substance, ds.node_id.to_numpy(), np.arange(3)[:, None])
            assert (ds.concentration.sel(substance=substance) == expected).all()

    df = model.basin.concentration_external.df
    assert df is not None
    assert len(df) == 3 * len(substances) * 4
    row = df[(df.node_id == 6) & (df.substance == "Cl")].iloc[-1]
    assert row.concentration == value("Cl", 6, 2)


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


junction_tracer_results = (
    delwaq_dir.parents[2] / "generated_testmodels/junction_tracer/results/flow.nc"
)


@pytest.mark.skipif(
    not junction_tracer_results.is_file(),
    reason="Requires junction_tracer model results.",
)
def test_junction_tracer_network():
    """Junction nodes that divide the flow are removed from the Delwaq network, with exchange flows per source."""
    toml_path = (
        delwaq_dir.parents[2] / "generated_testmodels/junction_tracer/ribasim.toml"
    )
    model = Model.read(toml_path)
    G, node_mapping, _link_mapping, _basin_mapping = _setup_graph(
        model.node,
        model.link,
        evaporate_mass=model.solver.evaporate_mass,
        routed_junction_ids=model.junction._routed_node_ids(),
    )
    assert all(d["type"] != "Junction" for _, d in G.nodes(data=True))

    flows = (
        xr.open_dataset(junction_tracer_results)["flow_rate"]
        .to_dataframe()
        .reset_index()
    )
    flows["time"] = (
        (flows["time"] - flows["time"].iloc[0]).dt.total_seconds().astype("int32")
    )
    term_flows = _junction_term_flows(G, flows)
    assert term_flows is not None
    edges = list(G.edges())

    # FlowBoundary #1 (0.04 m³/s) and #2 (0.02 m³/s) mix in Junction #3, of which 0.05 m³/s
    # flows on to Basin #7, so each FlowBoundary delivers its share of that
    for node_id, expected in ((1, 0.04 * 0.05 / 0.06), (2, 0.02 * 0.05 / 0.06)):
        i = edges.index((node_mapping[node_id], node_mapping[7]))
        flow = term_flows.loc[term_flows.link_id == i, "flow_rate"]
        assert len(flow) > 0
        assert np.allclose(flow, expected, rtol=1e-6)


def test_junction_group_one_basin():
    model = junction_bidirectional()
    G, _, _, basin_mapping = _setup_graph(model.node, model.link, evaporate_mass=False)
    df_link = model.link.df
    assert df_link is not None

    def link_id(from_node_id, to_node_id):
        df = df_link[
            (df_link.from_node_id == from_node_id) & (df_link.to_node_id == to_node_id)
        ]
        return df.index.item()

    # All neighbors of the group connect to Basin 1 with the flow of their own link.
    # Connectors are removed as well, so an outflow uses the link after the connector.
    basin_1 = basin_mapping[1]
    in_ids = {
        link_id
        for _, _, data in G.in_edges(basin_1, data=True)
        for link_id in data["id"]
    }
    out_ids = {
        link_id
        for _, _, data in G.out_edges(basin_1, data=True)
        for link_id in data["id"]
    }
    assert {link_id(4, 2), link_id(7, 3), link_id(10, 3)} <= in_ids
    assert {link_id(5, 6), link_id(8, 6)} <= out_ids
    # A UserDemand in both directions only has a link for the water it consumes, as
    # without Junctions: its inflow minus its return flow
    assert link_id(3, 9) in out_ids
    assert link_id(9, 3) not in in_ids
    (consumption,) = (
        d for _, _, d in G.out_edges(basin_1, data=True) if link_id(3, 9) in d["id"]
    )
    ratio = ([link_id(9, 3)], [link_id(3, 9)])
    assert consumption["terms"] == [(link_id(3, 9), [ratio], -1)]
    # The links of the group with the Basin and between its Junctions have no flow of their own
    assert not {link_id(1, 2), link_id(3, 2)} & (in_ids | out_ids)
    assert not any(data["type"] == "Junction" for _, data in G.nodes(data=True))
