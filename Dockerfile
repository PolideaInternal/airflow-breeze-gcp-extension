#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Using official python runtime base image
FROM ubuntu:18.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
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

# lsb
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lsb-release mysql-server libmysqlclient-dev libsasl2-dev mysql-client \
    && apt-get clean

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bzip2 unzip apt-transport-https xz-utils \
    && apt-get clean

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    openjdk-8-jdk  \
    && [ "$JAVA_HOME" = "$(docker-java-home)" ] \
    && apt-get clean

RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql postgresql-contrib \
    && apt-get clean

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python-pip python3-pip virtualenvwrapper \
    && apt-get clean

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git-all tig tmux vim less curl gnupg2 software-properties-common libpq-dev \
    && apt-get clean

RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" \
    && echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" \
    | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    |apt-key add - \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-sdk \
    && apt-get clean


# Install python 3.6 for airflow's compatibility,
# python-dev and necessary libraries to build all python packages
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install  -y --no-install-recommends \
       python3.6 python3.6-dev python3.5 python3.5-dev python-dev \
       build-essential autoconf libtool libkrb5-dev \
    && apt-get clean

WORKDIR /workspace
RUN mkdir -pv /airflow/dags
# Set airflow home
ENV AIRFLOW_HOME /airflow

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        mlocate \
    && apt-get clean

RUN updatedb

# Setup un-privileged user with passwordless sudo access.
RUN apt-get update && apt-get install -y --no-install-recommends sudo && apt-get clean
RUN groupadd -r airflow && useradd -m -r -g airflow -G sudo airflow
RUN echo 'airflow   ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

RUN apt-get update \
    && apt-get install python-setuptools python3-setuptools \
    && apt-get clean

RUN pip install --upgrade virtualenvwrapper \
   && pip3 install --upgrade virtualenvwrapper

RUN source /usr/share/virtualenvwrapper/virtualenvwrapper.sh \
    && mkvirtualenv -p /usr/bin/python3.6 airflow36  \
    && mkvirtualenv -p /usr/bin/python3.5 airflow35

## Preinstall airflow
## Airflow requires this variable be set on installation to avoid a GPL dependency.
ENV SLUGIFY_USES_TEXT_UNIDECODE yes

# Note. Increase this number to force rebuilding to the latest dependencies
ENV REBUILD_AIRFLOW_BREEZE_VERSION=6

ARG AIRFLOW_REPO_URL=https://github.com/apache/airflow
ARG AIRFLOW_REPO_BRANCH=master

RUN echo Checking out airflow source from ${AIRFLOW_REPO_URL}, branch: ${AIRFLOW_REPO_BRANCH}
RUN git clone ${AIRFLOW_REPO_URL} temp_airflow
RUN cd temp_airflow && git checkout ${AIRFLOW_REPO_BRANCH}

# Speed up the installation of cassandra driver
ENV CASS_DRIVER_BUILD_CONCURRENCY=8
ENV CASS_DRIVER_NO_CYTHON=1

RUN . /usr/share/virtualenvwrapper/virtualenvwrapper.sh \
    && cd temp_airflow \
    && workon airflow36 \
    && pip install --no-use-pep517 -e .[devel_ci]

RUN . /usr/share/virtualenvwrapper/virtualenvwrapper.sh \
    && cd temp_airflow \
    && workon airflow35 \
    && pip install --no-use-pep517 -e .[devel_ci]

RUN apt-get update && apt-get install -y --no-install-recommends jq && apt-get clean
RUN rm -rf temp_airflow

RUN mkdir -pv /airflow/output

RUN sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /etc/postgresql/10/main/postgresql.conf
RUN sed -i "s/127.0.0.1\/32/0.0.0.0\/0/" /etc/postgresql/10/main/pg_hba.conf

RUN pip install awscli botocore

## Add config and scripts
COPY airflow.cfg /airflow/airflow.cfg
COPY _init.sh /airflow/_init.sh
COPY _setup_gcp_key.sh /airflow/_setup_gcp_key.sh
COPY _reset.sh /airflow/_reset.sh
COPY _create_links.sh /airflow/_create_links.sh
COPY _setup_gcp_connection.py /airflow/_setup_gcp_connection.py
COPY _decrypt_encrypted_variables.sh /airflow/_decrypt_encrypted_variables.sh
COPY _bash_aliases /root/.bash_aliases
COPY _inputrc /root/.inputrc
COPY cloudbuild /root/cloudbuild
