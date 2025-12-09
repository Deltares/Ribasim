from pathlib import Path

import pytest
from ribasim import Model
from ribasim.db_utils import _get_db_schema_version

root_folder = Path(__file__).parent.parent.parent.parent
print(root_folder)


@pytest.mark.regression
def test_hws_migration(tmp_path):
    toml_path = root_folder / "models/hws_migration_test/hws.toml"
    db_path = root_folder / "models/hws_migration_test/database.gpkg"

    assert toml_path.exists(), (
        "Can't find the model, did you retrieve it with s3_download.py?"
    )

    assert _get_db_schema_version(db_path) == 0
    model = Model.read(toml_path)

    assert model.link.df.index.name == "link_id"
    assert len(model.link.df) == 454
    model.write(tmp_path / "hws_migrated.toml")


def test_active_migration():
    from pandas import DataFrame
    from ribasim.migrations import check_inactive

    df = DataFrame({"node_id": [1, 2, 3], "active": [True, False, None]})

    with pytest.raises(
        ValueError,
        match=r"Inactive node\(s\) with node_id \[2\] in test_nodes cannot be migrated automatically",
    ):
        check_inactive(df, "test_nodes")
