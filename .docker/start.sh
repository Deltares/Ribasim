#!/usr/bin/env bash
set -euxo pipefail

source .env

docker compose -f compose.yml up -d --force-recreate --remove-orphans
echo "Installation of the plugin Ribasim"
docker exec -t qgis sh -c "qgis_setup.sh ${PLUGIN_NAME}"
echo "Containers are running"
