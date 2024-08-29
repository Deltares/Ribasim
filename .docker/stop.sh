#!/usr/bin/env bash
set -eux

echo 'Stopping/killing containers'
docker compose -f compose.yml kill
docker compose -f compose.yml rm -f
