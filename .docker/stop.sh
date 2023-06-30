#!/usr/bin/env bash
set -euxo pipefail

echo 'Stopping/killing containers'
docker compose -f compose.yml kill
docker compose -f compose.yml rm -f
