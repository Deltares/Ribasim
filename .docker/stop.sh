#!/usr/bin/env bash
echo 'Stopping/killing containers'
docker compose -f compose.yml kill
docker compose -f compose.yml rm -f
