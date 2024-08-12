import logging
import sqlite3
from datetime import datetime
from pathlib import Path

STYLES_DIR = Path(__file__).parent / "styles"

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS "main"."layer_styles" (
    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "f_table_catalog" TEXT(256),
    "f_table_schema" TEXT(256),
    "f_table_name" TEXT(256),
    "f_geometry_column" TEXT(256),
    "styleName" TEXT(30),
    "styleQML" TEXT,
    "styleSLD" TEXT,
    "useAsDefault" BOOLEAN,
    "description" TEXT,
    "owner" TEXT(30),
    "ui" TEXT(30),
    "update_time" DATETIME DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
"""

INSERT_CONTENTS_SQL = """
INSERT INTO gpkg_contents (
    "table_name",
    "data_type",
    "identifier",
    "description",
    "last_change",
    "min_x",
    "min_y",
    "max_x",
    "max_y",
    "srs_id"
)
VALUES (
    'layer_styles',
    'attributes',
    'layer_styles',
    '',
    '',
    NULL,
    NULL,
    NULL,
    NULL,
    0
);
"""

INSERT_ROW_SQL = """
INSERT INTO "main"."layer_styles" (
    "f_table_catalog",
    "f_table_schema",
    "f_table_name",
    "f_geometry_column",
    "styleName",
    "styleQML",
    "styleSLD",
    "useAsDefault",
    "description",
    "owner",
    "ui",
    "update_time"
)
VALUES (
    '',
    '',
    :layer,
    'geom',
    :style_name,
    :style_qml,
    :style_sld,
    '1',
    :description,
    '',
    NULL,
    :update_date_time
);
"""

SQL_STYLES_EXIST = """
SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type="table" AND name="layer_styles");
"""


def _add_styles_to_geopackage(gpkg_path: Path, layer: str):
    with sqlite3.connect(gpkg_path) as conn:
        if not conn.execute(SQL_STYLES_EXIST).fetchone()[0]:
            conn.execute(CREATE_TABLE_SQL)
            conn.execute(INSERT_CONTENTS_SQL)

        style_name = f"{layer.replace(" / ", "_")}Style"
        style_qml = STYLES_DIR / f"{style_name}.qml"
        style_sld = STYLES_DIR / f"{style_name}.sld"

        if style_qml.exists() and style_sld.exists():
            description = f"Ribasim style for layer: {layer}"
            update_date_time = f"{datetime.now().isoformat()}Z"

            conn.execute(
                INSERT_ROW_SQL,
                {
                    "layer": layer,
                    "style_qml": style_qml.read_bytes(),
                    "style_sld": style_sld.read_bytes(),
                    "style_name": style_name,
                    "description": description,
                    "update_date_time": update_date_time,
                },
            )
        else:
            logging.warning(f"Style not found for layer: {layer}")
