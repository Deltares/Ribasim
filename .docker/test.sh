#!/usr/bin/env bash
set -euxo pipefail

export $(grep -v '^#' .env | xargs)

docker exec -t qgis sh -c "cd /tests_directory && qgis_testrunner.sh ${PLUGIN_NAME}.tests"
