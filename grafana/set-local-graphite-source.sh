#!/bin/bash
set -e

# waiting for grafana to get up and running, which takes longer on a first
# start or after an upgrade while it migrates its database
until curl -fsS -o /dev/null 'http://localhost:80/api/health'; do
  sleep 2
done

curl -X POST 'http://admin:admin@localhost:80/api/datasources' \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary '{
		"name":"Local Graphite",
		"type":"graphite",
		"url":"http://localhost:8000",
		"access":"proxy",
		"isDefault":true
	}'
