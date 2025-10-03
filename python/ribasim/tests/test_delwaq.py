import os
from pathlib import Path

import numpy as np
import pytest
from ribasim import Model
from ribasim.delwaq import add_tracer, generate, parse, run_delwaq
from ribasim.delwaq.util import model_dir

delwaq_dir = Path(__file__).parent


@pytest.mark.skipif(
    not (
        ("D3D_HOME" in os.environ)
        and (
            delwaq_dir.parents[2] / "generated_testmodels/basic/results/flow.arrow"
        ).is_file()
    ),
    reason="Requires Delwaq to be installed and basic model results.",
)
def test_offline_delwaq_coupling():
    repo_dir = delwaq_dir.parents[2]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"

    model = Model.read(toml_path)

    # With evaporation of mass disabled
    model.solver.evaporate_mass = False
    graph, substances = generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, graph, substances, model_dir)

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

    # With evaporation of mass disabled
    model.solver.evaporate_mass = True
    add_tracer(model, 11, "Foo")
    add_tracer(model, 15, "Bar")

    graph, substances = generate(model, model_dir)
    run_delwaq(model_dir)
    model = parse(model, graph, substances, model_dir)

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
        "Tracer",
        "UserDemand",
    ]

    assert all(np.isclose(df[df.substance == "Continuity"].concentration, 1.0))
    assert all(np.isclose(df[df.substance == "UserDemand"].concentration, 0.0))

    model.write(toml_path)
