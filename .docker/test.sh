#!/usr/bin/env bash
# Run the QGIS plugin tests inside an official QGIS docker image, e.g.:
#
#   bash .docker/test.sh qgis/qgis:3.44
#   bash .docker/test.sh qgis/qgis:4.2
#
# The plugin is mounted at /tests_directory/ribasim_qgis, where qgis_setup.sh
# expects it to be.
set -euo pipefail

IMAGE=${1:?usage: test.sh <qgis docker image>}
DOCKER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "${DOCKER_DIR}")

docker run --rm \
    --platform linux/amd64 \
    --env CI=true \
    --volume "${REPO_DIR}/ribasim_qgis:/tests_directory/ribasim_qgis" \
    --volume "${DOCKER_DIR}:/tests_directory/.docker:ro" \
    "${IMAGE}" \
    bash /tests_directory/.docker/run_tests.sh
