from pathlib import Path

from build_piave_wflow import download


def test_download_once(tmp_path: Path):
    source = tmp_path / "source" / "irrigated_area.tif"
    source.parent.mkdir()
    source.write_bytes(b"first")
    directory = tmp_path / "models" / "data"

    path = download(source.as_uri(), directory)

    assert path == directory / "irrigated_area.tif"
    assert path.read_bytes() == b"first"

    # An existing file is not downloaded again
    source.write_bytes(b"second")
    assert download(source.as_uri(), directory).read_bytes() == b"first"
