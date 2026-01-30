#!/usr/bin/env bash
set -eux

docker compose -f compose.yml up -d --force-recreate --remove-orphans

echo "Downloading QGIS test runner scripts (not included in qgis/qgis:3.40 image)"
docker exec -t qgis sh -c "wget -q -P /usr/bin https://raw.githubusercontent.com/qgis/QGIS/refs/tags/ltr-3_40/.docker/qgis_resources/test_runner/qgis_setup.sh && chmod +x /usr/bin/qgis_setup.sh"
docker exec -t qgis sh -c "wget -q -P /usr/bin https://raw.githubusercontent.com/qgis/QGIS/refs/tags/ltr-3_40/.docker/qgis_resources/test_runner/qgis_testrunner.sh && chmod +x /usr/bin/qgis_testrunner.sh"
docker exec -t qgis sh -c "wget -q -P /usr/bin https://raw.githubusercontent.com/qgis/QGIS/refs/tags/ltr-3_40/.docker/qgis_resources/test_runner/qgis_startup.py"
docker exec -t qgis sh -c "wget -q -P /usr/bin https://raw.githubusercontent.com/qgis/QGIS/refs/tags/ltr-3_40/.docker/qgis_resources/test_runner/qgis_testrunner.py"

docker exec -t qgis sh -c "apt install -y python3-pandas"

echo "Installation of the plugin Ribasim"
docker exec -t qgis sh -c "qgis_setup.sh ribasim_qgis"
echo "Containers are running"

docker exec -t qgis sh -c "python3 -m pip install pandas"
docker exec -t qgis sh -c "cd /tests_directory && xvfb-run -a qgis_testrunner.sh ribasim_qgis.tests"
exit_code=$?

echo 'Stopping/killing containers'
docker compose -f compose.yml kill
docker compose -f compose.yml rm -f

exit $exit_code
