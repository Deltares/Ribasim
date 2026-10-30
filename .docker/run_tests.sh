#!/usr/bin/env bash
# Runs inside a qgis/qgis docker container (see test.sh): installs the plugin
# dependencies, enables the plugin in a QGIS profile, and runs the pytest suite
# inside a single QGIS process.
set -euo pipefail

QGIS_MAJOR=$(python3 -c "from qgis.core import Qgis; print(Qgis.versionInt() // 10000)")

# The plot widget needs a web view, which the images don't include.
if [ "${QGIS_MAJOR}" = "3" ]; then
    WEBENGINE=python3-pyqt5.qtwebengine
else
    WEBENGINE=python3-pyqt6.qtwebengine
fi

echo "Installing plugin dependencies"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3-pandas python3-pytest python3-netcdf4 python3-plotly "${WEBENGINE}" > /dev/null

echo "Setting up QGIS profile with the ribasim_qgis plugin enabled"
qgis_setup.sh ribasim_qgis

# qgis_setup.sh always writes the QGIS3 profile, but QGIS 4 reads
# ~/.local/share/QGIS/QGIS4/profiles/default/QGIS/QGIS4.ini.
if [ "${QGIS_MAJOR}" != "3" ]; then
    QGIS_DIR=/root/.local/share/QGIS
    mv "${QGIS_DIR}/QGIS3" "${QGIS_DIR}/QGIS${QGIS_MAJOR}"
    mv "${QGIS_DIR}/QGIS${QGIS_MAJOR}/profiles/default/QGIS/QGIS3.ini" \
        "${QGIS_DIR}/QGIS${QGIS_MAJOR}/profiles/default/QGIS/QGIS${QGIS_MAJOR}.ini"
fi

# QtWebEngine's Chromium sandbox cannot run as root in a container.
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu"

cd /tests_directory/ribasim_qgis/tests
QGIS_TEST_MODULE=ribasim_qgis.tests xvfb-run -a qgis --nologo \
    --code /tests_directory/ribasim_qgis/scripts/qgis_testrunner.py
