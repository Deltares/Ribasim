from pathlib import Path

from generate import generate
from util import run_delwaq

delwaq_dir = Path(__file__).parent


def test_offline_delwaq_coupling():
    repo_dir = delwaq_dir.parents[1]
    modelfn = repo_dir / "generated_testmodels/basic/ribasim.toml"

    graph, substances = generate(modelfn)
    run_delwaq()
    # parse(model, graph, substances)
