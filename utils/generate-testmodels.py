import multiprocessing
import shutil
import sys
from functools import partial
from pathlib import Path

import ribasim_testmodels

selection = (
    sys.argv[1:] if len(sys.argv) > 1 else ribasim_testmodels.constructors.keys()
)


def generate_model(args, datadir):
    model_name, model_constructor = args
    model = model_constructor()
    model.write(datadir / model_name / "ribasim.toml")
    return model_name


if __name__ == "__main__":
    datadir = Path("generated_testmodels")
    # Don't remove all models if we only (re)generate a subset
    if datadir.is_dir() and len(sys.argv) == 0:
        shutil.rmtree(datadir, ignore_errors=True)

    datadir.mkdir(exist_ok=True)
    readme = datadir / "README.md"
    readme.write_text(
        """\
# Ribasim testmodels

The content of this directory are generated testmodels for Ribasim
Don't put important stuff in here, it will be emptied for every run."""
    )

    generate_model_partial = partial(generate_model, datadir=datadir)

    models = [
        (k, v) for k, v in ribasim_testmodels.constructors.items() if k in selection
    ]

    with multiprocessing.Pool(processes=4) as p:
        for model_name in p.imap_unordered(generate_model_partial, models):
            print(f"Generated {model_name}")
