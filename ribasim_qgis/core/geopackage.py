"""
Geopackage management utilities.

This module lightly wraps a QGIS built in functions to:

    * List the layers of a geopackage

"""

import sqlite3
from contextlib import contextmanager
from pathlib import Path


@contextmanager
def sqlite3_cursor(path: Path):
    connection = sqlite3.connect(path)
    cursor = connection.cursor()
    try:
        yield cursor
    finally:
        cursor.close()
        connection.commit()
        connection.close()


def layers(path: Path) -> list[str]:
    """
    Return all layers that are present in the geopackage.

    Parameters
    ----------
    path: Path
        Path to the geopackage

    Returns
    -------
    layernames: list[str]
    """
    with sqlite3_cursor(path) as cursor:
        cursor.execute("Select table_name from gpkg_contents")
        layers = [item[0] for item in cursor.fetchall()]
    return layers
