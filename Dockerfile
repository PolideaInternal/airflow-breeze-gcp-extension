# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Using official python runtime base image
FROM python:2.7.12

RUN apt-get update

# lsb
RUN apt-get install -y --no-install-recommends lsb-release

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libmysqlclient-dev
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libsasl2-dev

# MySQL Client for CloudSQL setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 \
    unzip \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*
RUN echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list
RUN set -x \
  && apt-get update \
  && apt-get install -y \
    mysql-client \
  && rm -rf /var/lib/apt/lists/*

# Java installation.
ENV LANG C.UTF-8
# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
    echo '#!/bin/sh'; \
    echo 'set -e'; \
    echo; \
    echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
  } > /usr/local/bin/docker-java-home \
  && chmod +x /usr/local/bin/docker-java-home
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
RUN set -x \
  && apt-get update \
  && apt-get install -y -t jessie-backports openjdk-8-jdk \
  && rm -rf /var/lib/apt/lists/* \
  && [ "$JAVA_HOME" = "$(docker-java-home)" ]
# see CA_CERTIFICATES_JAVA_VERSION notes above
RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure

# Install Google Cloud SDK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-transport-https
RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" \
    && echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" \
    | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    |apt-key add - \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-sdk

# Postgres for localexecutor
RUN apt-get -y install postgresql postgresql-contrib

# Add on python dependencies.
RUN pip install --upgrade pip
RUN pip install google-cloud-dataflow
RUN pip install google-cloud-storage
RUN pip install cryptography
RUN pip install pyyaml
RUN pip install iso8601
RUN pip install celery[redis]
RUN pip install pandas-gbq

RUN pip install tensorflow
RUN pip install tensorflow-transform
RUN pip install pandas
RUN pip install virtualenv
RUN pip install unicodecsv
RUN pip install pyOpenSSL==16.2.0
RUN pip install alembic
RUN pip install kerberos
RUN pip install requests_kerberos
RUN pip install docker
RUN pip install hdfs

WORKDIR /home/airflow
RUN mkdir -p /home/airflow/dags

# Preinstall airflow
# Airflow requires this variable be set on installation to avoid a GPL dependency.
ENV SLUGIFY_USES_TEXT_UNIDECODE yes
RUN git clone https://github.com/apache/incubator-airflow.git temp_airflow
RUN cd temp_airflow && pip install -e .[devel,gcp_api,postgres,hive,crypto,celery,rabbitmq,kerberos,hdfs]
RUN rm -rf temp_airflow

# Set airflow home
ENV AIRFLOW_HOME /home/airflow

# Setup un-privileged user with passwordless sudo access.
RUN apt-get update && apt-get install -y --no-install-recommends sudo
RUN groupadd -r airflow && useradd -m -r -g airflow -G sudo airflow
RUN echo 'airflow\tALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
USER airflow

# Add useful tools
RUN sudo apt-get -y install git-all tig tmux vim less

# Add config and scripts
COPY airflow.cfg /home/airflow
COPY _init.sh /home/airflow
COPY _setup_gcp_connection.py /home/airflow

