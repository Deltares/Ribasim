import shutil
from pathlib import Path

import ribasim_testmodels

if __name__ == "__main__":
    datadir = Path("generated_testmodels")
    if datadir.is_dir():
        shutil.rmtree(datadir)

    datadir.mkdir()
    readme = datadir / "README.md"
    readme.write_text(
        """\
# Ribasim testmodels

The content of this directory are generated testmodels for Ribasim
Don't put important stuff in here, it will be emptied for every run."""
    )

    models = [
        model_generator()
        for model_generator in map(
            ribasim_testmodels.__dict__.get, ribasim_testmodels.__all__
        )
    ]

    for model in models:
        model.write(datadir / model.modelname)
