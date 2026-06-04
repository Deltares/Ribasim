import os
import subprocess

qgis_process = subprocess.run(
    [
        "qgis",
        "--profiles-path",
        ".pixi/qgis_env",
        "--version-migration",
        "--nologo",
        "--code",
        "ribasim_qgis/scripts/qgis_testrunner.py",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    env={**os.environ, "QGIS_TEST_MODULE": "ribasim_qgis.tests"},
)

print(qgis_process.stdout)
qgis_process.check_returncode()
