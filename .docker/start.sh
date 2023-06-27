#!/usr/bin/env bash
docker compose -f compose.yml up -d --force-recreate --remove-orphans
echo "Wait 10 seconds"
sleep 10
echo "Installation of the plugin Ribasim"
docker exec -t qgis sh -c "qgis_setup.sh ribasim_qgis"
echo "Containers are running"
