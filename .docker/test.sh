#!/usr/bin/env bash
set -eux

docker exec -t qgis sh -c "cd /tests_directory && xvfb-run -a qgis_testrunner.sh ribasim_qgis.tests"
