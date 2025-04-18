FROM     python:3.9-bookworm AS base

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND=noninteractive

# Install all prerequisites
RUN apt-get -y update

# See https://grafana.com/docs/grafana/latest/installation/debian/
RUN apt-get install -y apt-transport-https software-properties-common curl && \
    curl -sSf https://packages.grafana.com/gpg.key | apt-key add - && \
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list && \
    apt-get -y update && apt-get -y install supervisor nginx-light grafana=11.6.0 build-essential

# The official original statsd package https://www.npmjs.com/package/statsd
RUN apt-get -y install nodejs npm && \
    npm install --global statsd@0.9.0

# See https://github.com/graphite-project/graphite-web/blob/1.1.x/docs/install-pip.rst
ENV PYTHONPATH="/opt/graphite/lib/:/opt/graphite/webapp/"
RUN apt-get -y install libffi-dev libcairo2 build-essential && \
    pip install --no-cache-dir gunicorn==23.0.0 flit_core==3.12.0 && \
    pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/whisper/tarball/1.1.10 && \
    pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/carbon/tarball/1.1.10 && \
    pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/graphite-web/tarball/1.1.10

# ----------------- #
#   Configuration   #
# ----------------- #

FROM base

# Confiure StatsD
COPY    ./statsd/config.js /src/statsd/config.js

# Configure Whisper, Carbon and Graphite-Web
COPY ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
COPY ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
COPY ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
COPY ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
COPY ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN mkdir -p /opt/graphite/storage/whisper && \
    touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index && \
    chown -R www-data /opt/graphite/storage && \
    chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper && \
    chmod 0664 /opt/graphite/storage/graphite.db && \
    django-admin migrate --settings=graphite.settings

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
