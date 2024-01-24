import subprocess
import sys

xvfb = ["xvfb-run", "-a"] if sys.platform == "linux" else []
qgis_command = [
    "qgis",
    "--profiles-path",
    ".pixi/qgis_env",
    "--version-migration",
    "--nologo",
    "--code",
    "ribasim_qgis/scripts/qgis_testrunner.py",
    "ribasim_qgis.tests",
]

qgis_process = subprocess.run(
    xvfb + qgis_command,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

print(qgis_process.stdout)
qgis_process.check_returncode()
if any(s in qgis_process.stdout for s in ["QGIS died on signal", "FAILED"]):
    exit(1)
