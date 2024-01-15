#!/usr/bin/env bash
set -euxo pipefail

source .env

docker exec -t qgis sh -c "cd /tests_directory && qgis_testrunner.sh ${PLUGIN_NAME}.tests && sleep 5"
