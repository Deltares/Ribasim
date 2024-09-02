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
        "ribasim_qgis.tests",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

print(qgis_process.stdout)
qgis_process.check_returncode()

# QGIS always finishes with exit code 0, even when tests fail, so we have to check the output
if any(s in qgis_process.stdout for s in ["QGIS died on signal", "FAILED"]):
    exit(1)
