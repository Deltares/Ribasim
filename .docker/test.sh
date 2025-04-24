#!/usr/bin/env bash
set -eux

docker compose -f compose.yml up -d --force-recreate --remove-orphans
echo "Installation of the plugin Ribasim"
docker exec -t qgis sh -c "qgis_setup.sh ribasim_qgis"
echo "Containers are running"

docker exec -t qgis sh -c "cd /tests_directory && xvfb-run -a qgis_testrunner.sh ribasim_qgis.tests"
exit_code=$?

echo 'Stopping/killing containers'
docker compose -f compose.yml kill
docker compose -f compose.yml rm -f

exit $exit_code
