#!/usr/bin/env bash
docker exec -t qgis sh -c "cd /tests_directory && qgis_testrunner.sh ribasim_qgis.tests.test_io"
