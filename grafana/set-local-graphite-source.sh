#!/bin/bash
set -e

# sleeping for 10 seconds to let grafana get up and running
sleep 10

curl -X POST 'http://admin:admin@localhost:80/api/datasources' \
	-H 'Content-Type: application/json;charset=UTF-8' \
	--data-binary '{
		"name":"Local Graphite",
		"type":"graphite",
		"url":"http://localhost:8000",
		"access":"proxy",
		"isDefault":true
	}'
