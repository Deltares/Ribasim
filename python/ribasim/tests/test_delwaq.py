import os
from pathlib import Path

import pytest
from ribasim import Model
from ribasim.delwaq import add_tracer, generate, parse, run_delwaq

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
    add_tracer(model, 11, "Foo")
    add_tracer(model, 15, "Bar")
    model.write(toml_path)

    graph, substances = generate(toml_path)
    run_delwaq()
    model = parse(toml_path, graph, substances)

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
        "Terminal",
        "Tracer",
        "UserDemand",
    ]
