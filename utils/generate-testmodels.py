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

    for model_name, model_constructor in ribasim_testmodels.constructors.items():
        model = model_constructor()
        model.write(datadir / model_name)
