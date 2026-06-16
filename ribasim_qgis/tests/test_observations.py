"""Tests for ribasim_qgis.core.observations — reading Observation input data."""

import sqlite3
from pathlib import Path

import numpy as np
import pytest

from ribasim_qgis.core.observations import (
    OBSERVATION_TABLE,
    Observations,
    read_observations,
)


def _write_observation_gpkg(path: Path, rows: list[tuple]) -> None:
    """Create a minimal sqlite GeoPackage with an ``Observation / time`` table."""
    con = sqlite3.connect(path)
    try:
        con.execute(
            f'CREATE TABLE "{OBSERVATION_TABLE}" ('
            "fid INTEGER PRIMARY KEY, node_id INTEGER, variable TEXT, "
            "time TIMESTAMP, value REAL)"
        )
        con.executemany(
            # OBSERVATION_TABLE is a trusted module constant, not user input.
            f'INSERT INTO "{OBSERVATION_TABLE}" '  # noqa: S608
            "(node_id, variable, time, value) VALUES (?, ?, ?, ?)",
            rows,
        )
        con.commit()
    finally:
        con.close()


@pytest.fixture
def observation_gpkg(tmp_path: Path) -> Path:
    path = tmp_path / "database.gpkg"
    _write_observation_gpkg(
        path,
        [
            (4, "level", "2020-01-01 00:00:00", 0.5),
            (4, "level", "2020-02-01 00:00:00", 0.3),
            (4, "level", "2020-03-01 00:00:00", 0.4),
            (5, "flow_rate", "2020-01-01 00:00:00", 0.0),
            (5, "flow_rate", "2020-02-01 00:00:00", 0.05),
        ],
    )
    return path


def test_read_observations_returns_observations(observation_gpkg: Path):
    observations = read_observations(observation_gpkg)
    assert isinstance(observations, Observations)


def test_read_observations_variables(observation_gpkg: Path):
    observations = read_observations(observation_gpkg)
    assert observations is not None
    assert observations.variables == {"level", "flow_rate"}


def test_read_observations_data_grouping(observation_gpkg: Path):
    observations = read_observations(observation_gpkg)
    assert observations is not None
    assert set(observations.data) == {4, 5}
    assert set(observations.data[4]) == {"level"}
    assert set(observations.data[5]) == {"flow_rate"}


def test_read_observations_series_values(observation_gpkg: Path):
    observations = read_observations(observation_gpkg)
    assert observations is not None
    times, values = observations.data[4]["level"]
    np.testing.assert_array_equal(
        times,
        ["2020-01-01T00:00:00", "2020-02-01T00:00:00", "2020-03-01T00:00:00"],
    )
    np.testing.assert_allclose(values, [0.5, 0.3, 0.4])


def test_observations_series_helper(observation_gpkg: Path):
    observations = read_observations(observation_gpkg)
    assert observations is not None
    series = observations.series(5, "flow_rate")
    assert series is not None
    _, values = series
    np.testing.assert_allclose(values, [0.0, 0.05])
    assert observations.series(99, "level") is None
    assert observations.series(4, "missing") is None


def test_read_observations_missing_file(tmp_path: Path):
    assert read_observations(tmp_path / "nope.gpkg") is None


def test_read_observations_no_table(tmp_path: Path):
    path = tmp_path / "empty.gpkg"
    sqlite3.connect(path).close()
    assert read_observations(path) is None


def test_read_observations_empty_table(tmp_path: Path):
    path = tmp_path / "empty_table.gpkg"
    _write_observation_gpkg(path, [])
    assert read_observations(path) is None
