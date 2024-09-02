#!/usr/bin/env bash
set -eux

docker compose -f compose.yml up -d --force-recreate --remove-orphans
echo "Installation of the plugin Ribasim"
docker exec -t qgis sh -c "qgis_setup.sh ribasim_qgis"
echo "Containers are running"
