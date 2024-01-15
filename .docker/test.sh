#!/usr/bin/env bash
set -euxo pipefail

source .env

docker exec -t qgis sh -c "cd /tests_directory && xvfb-run -a qgis_testrunner.sh ${PLUGIN_NAME}.tests"
