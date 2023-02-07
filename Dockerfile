FROM     ubuntu:22.10

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND noninteractive

# Install all prerequisites
RUN apt-get -y update

# See https://grafana.com/docs/grafana/latest/installation/debian/
RUN apt-get install -y apt-transport-https
RUN apt-get install -y software-properties-common curl
RUN curl -sSf https://packages.grafana.com/gpg.key | apt-key add -
RUN echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
RUN apt-get -y update
RUN apt-get -y install supervisor nginx-light grafana=8.1.3 build-essential

# The official original statsd package https://www.npmjs.com/package/statsd
RUN apt-get -y install nodejs npm
RUN npm install statsd@0.9.0

# See https://github.com/graphite-project/graphite-web/blob/1.1.x/docs/install-pip.rst
RUN apt-get -y install python3-pip gunicorn python3-dev libffi-dev libcairo2
ENV PYTHONPATH="/opt/graphite/lib/:/opt/graphite/webapp/"
RUN pip install --no-binary=:all: https://github.com/graphite-project/whisper/tarball/1.1.8 && \
    pip install --no-binary=:all: https://github.com/graphite-project/carbon/tarball/1.1.8 && \
    pip install --no-binary=:all: https://github.com/graphite-project/graphite-web/tarball/1.1.8

# ----------------- #
#   Configuration   #
# ----------------- #

# Confiure StatsD
ADD     ./statsd/config.js /src/statsd/config.js

# Configure Whisper, Carbon and Graphite-Web
ADD     ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
ADD     ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
ADD     ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
ADD     ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
ADD     ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN     mkdir -p /opt/graphite/storage/whisper
RUN     touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index
RUN     chown -R www-data /opt/graphite/storage
RUN     chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper
RUN     chmod 0664 /opt/graphite/storage/graphite.db
RUN     django-admin migrate --settings=graphite.settings

# Configure Grafana
ADD     ./grafana/custom.ini /etc/grafana/grafana.ini

# Add the default dashboards
RUN     mkdir /src/dashboards
ADD     ./grafana/dashboards/* /src/dashboards/
ADD     ./grafana/set-local-graphite-source.sh /src/
RUN     mkdir /src/dashboard-loader
ADD     ./grafana/dashboard-loader/dashboard-loader.js /src/dashboard-loader/

# Configure nginx and supervisord
ADD     ./nginx/nginx.conf /etc/nginx/nginx.conf
ADD     ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf


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

CMD     ["/usr/bin/supervisord"]

