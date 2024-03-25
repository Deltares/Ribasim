import multiprocessing
import os
import shutil
from functools import partial
from pathlib import Path

import ribasim_testmodels
from alive_progress import alive_bar


def generate_model(args, datadir):
    model_name, model_constructor = args
    model = model_constructor()
    model.write(datadir / model_name / "ribasim.toml")
    return model_name


if __name__ == "__main__":
    datadir = Path("generated_testmodels")
    if datadir.is_dir():
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

    testmodels = list(ribasim_testmodels.constructors.items())
    cpu_count = os.cpu_count()
    number_processes = 4 if cpu_count is None else int(cpu_count / 2)
    with (
        alive_bar(len(testmodels)) as bar,
        multiprocessing.Pool(number_processes) as p,
    ):
        for model_name in p.imap_unordered(generate_model_partial, testmodels):
            print(f"Generated {model_name}")
            bar()
