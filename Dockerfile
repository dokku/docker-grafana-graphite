FROM     grafana/grafana:13.2.4-ubuntu AS grafana

FROM     python:3.11-bookworm AS base

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND=noninteractive

# Install all prerequisites
RUN apt-get -y update && \
    apt-get -y install supervisor nginx-light build-essential

# Grafana, copied from its own ubuntu image, whose binary is built against
# glibc as this one is. See https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/
COPY --from=grafana /usr/share/grafana /usr/share/grafana
RUN ln -s /usr/share/grafana/bin/grafana /usr/local/bin/grafana && \
    mkdir -p /opt/grafana/data

# The official original statsd package https://www.npmjs.com/package/statsd
COPY ./statsd/package.json ./statsd/package-lock.json /src/statsd/
RUN apt-get -y install nodejs npm && \
    npm ci --omit=dev --prefix /src/statsd

# See https://github.com/graphite-project/graphite-web/blob/1.1.x/docs/install-pip.rst
# Graphite is installed into site-packages, since its /opt/graphite prefix is
# only honoured by the setup.py install that pip and uv no longer run, and is
# pointed at /opt/graphite for its configuration and data instead
ENV GRAPHITE_ROOT=/opt/graphite \
    GRAPHITE_CONF_DIR=/opt/graphite/conf \
    GRAPHITE_STORAGE_DIR=/opt/graphite/storage \
    GRAPHITE_SETTINGS_MODULE=local_settings \
    PYTHONPATH=/opt/graphite/webapp
ENV UV_PROJECT_ENVIRONMENT=/usr/local
COPY ./pyproject.toml ./uv.lock /src/python/
# uv is installed with pip since it publishes no image for arm/v7. Its version
# is the one pinned in pyproject.toml's build group, where dependabot bumps it
# hadolint ignore=DL3013
RUN apt-get -y install libffi-dev libcairo2 && \
    pip install --no-cache-dir "$(grep -o '"uv==[^"]*"' /src/python/pyproject.toml | tr -d '"')" && \
    uv sync --project /src/python --locked --no-dev --inexact --no-cache

# ----------------- #
#   Configuration   #
# ----------------- #

FROM base

# Confiure StatsD
COPY    ./statsd/config.js /src/statsd/config.js

# Configure Whisper, Carbon and Graphite-Web
COPY ./graphite/local_settings.py /opt/graphite/webapp/local_settings.py
COPY ./graphite/prepare-database.py /src/graphite/prepare-database.py
COPY ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
COPY ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
COPY ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
# graphite-web's static content is installed beside the interpreter, and is
# linked where nginx serves it from
RUN ln -s "$(python3 -c 'import sys; print(sys.prefix)')/webapp/content" /opt/graphite/webapp/content && \
    mkdir -p /opt/graphite/storage/whisper /opt/graphite/storage/log/webapp && \
    touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index && \
    chown -R www-data /opt/graphite/storage && \
    chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper && \
    chmod 0664 /opt/graphite/storage/graphite.db && \
    django-admin migrate --noinput --settings=graphite.settings

# Configure Grafana
COPY    ./grafana/custom.ini /etc/grafana/grafana.ini

# Add the default dashboards
RUN     mkdir /src/dashboards
COPY    ./grafana/dashboards/* /src/dashboards/
COPY    ./grafana/set-local-graphite-source.sh /src/
RUN     mkdir /src/dashboard-loader
COPY    ./grafana/dashboard-loader/dashboard-loader.js /src/dashboard-loader/

# Configure nginx and supervisord
COPY    ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY    ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# ---------------- #
#   Expose Ports   #
# ---------------- #

# Grafana
EXPOSE  80

# Graphite
EXPOSE 2003

# StatsD UDP port
EXPOSE  8125/udp

# StatsD Management port
EXPOSE  8126

# Graphite web port
EXPOSE 81



# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
