import os
from pathlib import Path

import pytest
from ribasim.delwaq import generate, parse, run_delwaq

delwaq_dir = Path(__file__).parent


@pytest.mark.skipif(
    not bool(os.getenv("D3D_HOME")), reason="Requires Delwaq to be installed."
)
def test_offline_delwaq_coupling():
    repo_dir = delwaq_dir.parents[2]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"

    graph, substances = generate(toml_path)
    run_delwaq()
    model = parse(toml_path, graph, substances)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == [
        "Basin",
        "Cl",
        "Continuity",
        "FlowBoundary",
        "LevelBoundary",
        "Terminal",
        "Tracer",
    ]
