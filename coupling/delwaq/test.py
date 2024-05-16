from pathlib import Path

from generate import generate
from parse import parse
from util import run_delwaq

delwaq_dir = Path(__file__).parent


def test_offline_delwaq_coupling():
    repo_dir = delwaq_dir.parents[1]
    modelfn = repo_dir / "generated_testmodels/basic/ribasim.toml"

    graph, substances = generate(modelfn)
    run_delwaq()
    model = parse(modelfn, graph, substances)
    df = model.basin.concentrationexternal

    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == ["Cl", "Continuity", "Tracer"]
