from pathlib import Path

from generate import generate
from parse import parse
from util import run_delwaq

delwaq_dir = Path(__file__).parent


def test_offline_delwaq_coupling():
    repo_dir = delwaq_dir.parents[1]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"

    graph, substances = generate(toml_path)
    run_delwaq()
    model = parse(toml_path, graph, substances)

    df = model.basin.concentration_external.df
    assert df is not None
    assert df.shape[0] > 0
    assert df.node_id.nunique() == 4
    assert sorted(df.substance.unique()) == ["Cl", "Continuity", "Tracer"]
