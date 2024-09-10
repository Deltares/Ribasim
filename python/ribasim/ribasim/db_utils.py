from contextlib import closing
from pathlib import Path
from sqlite3 import Connection, connect


def esc_id(identifier: str) -> str:
    """Escape SQLite identifiers."""
    identifier = identifier.replace('"', '""')
    return f'"{identifier}"'


def exists(connection: Connection, name: str) -> bool:
    """Check if a table exists in a SQLite database."""
    with closing(connection.cursor()) as cursor:
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
        )
        result = cursor.fetchone()
    return result is not None


def _set_gpkg_attribute_table(connection: Connection, table: str) -> None:
    # Set geopackage attribute table
    with closing(connection.cursor()) as cursor:
        sql = "INSERT OR REPLACE INTO gpkg_contents (table_name, data_type, identifier) VALUES (?, ?, ?)"
        cursor.execute(sql, (table, "attributes", table))
    connection.commit()


CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS ribasim_metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);
"""


def _get_db_schema_version(db_path: Path) -> int:
    """
    Get the schema version of the database.

    For older models, the version is assumed to be zero,
    which is smaller than the initial schema version of the database.
    """
    with closing(connect(db_path)) as connection:
        if not exists(connection, "ribasim_metadata"):
            return 0
        with closing(connection.cursor()) as cursor:
            cursor.execute(
                "SELECT value FROM ribasim_metadata WHERE key='schema_version'"
            )
            return int(cursor.fetchone()[0])


def _set_db_schema_version(db_path: Path, version: int = 1) -> None:
    with closing(connect(db_path)) as connection:
        if not exists(connection, "metadata"):
            with closing(connection.cursor()) as cursor:
                cursor.execute(CREATE_TABLE_SQL)
                cursor.execute(
                    "INSERT OR REPLACE INTO ribasim_metadata (key, value) VALUES ('schema_version', ?)",
                    (version,),
                )
            _set_gpkg_attribute_table(connection, "ribasim_metadata")
            connection.commit()
