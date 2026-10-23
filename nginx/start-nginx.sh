#!/bin/bash
set -e

# nginx is what answers on graphite-web's port, so it is only started once
# graphite-web answers behind it. A client that can connect is then one whose
# reads of the metrics get an answer rather than a bad gateway, which is what a
# check that only connects to the port takes to mean the container is ready.
#
# grafana is not waited for: the first time it starts it creates its database,
# which can take minutes, and until it is up its port answers with a bad gateway
until curl -fsS -o /dev/null 'http://127.0.0.1:8000/metrics/find?query=*'; do
  sleep 1
done

exec /usr/sbin/nginx
