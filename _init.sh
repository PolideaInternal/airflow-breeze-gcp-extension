#!/usr/bin/env bash
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
# cd, install from source, and setup postgres

# Make sure all environment variables created below are exported
# even if they are not explicitly exported (just in case)

. /usr/share/virtualenvwrapper/virtualenvwrapper.sh

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -euo pipefail

# Automatically export all variables
set -a

# Airflow requires this variable be set during installation to avoid a GPL
# dependency.
export SLUGIFY_USES_TEXT_UNIDECODE=yes

AIRFLOW_BREEZE_CONFIG_DIR="${HOME}/airflow-breeze-config"
if [[ -f ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env ]]; then
  echo "Sourcing variables from ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env"
  set -x
  source ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env
  set +x
fi

PYTHON_VERSION=${PYTHON_VERSION:=2.7}

if [[ "${PYTHON_VERSION}" = "2.7" ]]; then
  echo "Python 2.7 used"
  echo
  set +ue
  workon airflow27
  set -ue
elif [[ "${PYTHON_VERSION}" = "3.5" ]]; then
  echo
  echo "Python 3.5 used"
  echo
  set +ue
  workon airflow35
  set -ue
else
  echo
  echo "Python 3.6 used"
  echo
  set +ue
  workon airflow36
  set -ue
fi

cd /workspace

pip install -e .[devel_ci] \
  && sudo service postgresql start \
  && sudo -u postgres createuser root \
  && sudo -u postgres createdb airflow/airflow.db

export GCP_SERVICE_ACCOUNT_KEY_NAME=${GCP_SERVICE_ACCOUNT_KEY_NAME:=""}
alias set_gcp_key=". /airflow/_setup_gcp_key.sh"

. ${MY_DIR}/_setup_gcp_key.sh "${GCP_SERVICE_ACCOUNT_KEY_NAME}"

export AIRFLOW_HOME=${AIRFLOW_HOME:=/airflow}
export AIRFLOW_BREEZE_CONFIG_DIR=${AIRFLOW_BREEZE_CONFIG_DIR:=${HOME}/airflow-breeze-config}
export GCP_SERVICE_ACCOUNT_KEY_DIR=${AIRFLOW_BREEZE_CONFIG_DIR}/keys

export AIRFLOW_SOURCES="${AIRFLOW_SOURCES:=/workspace}"

# Enable local executor
export AIRFLOW_CONFIG=${AIRFLOW_SOURCES}/tests/contrib/operators/postgres_local_executor.cfg

# Source all environment variables from key dir
for ENV_FILE in ${GCP_SERVICE_ACCOUNT_KEY_DIR}/*.env
do
    if [[ -f ${ENV_FILE} ]]; then
        source ${ENV_FILE}
        echo
        cat ${ENV_FILE}
        echo
    fi
done

if [[ -f ${AIRFLOW_SOURCES}/decrypted_variables.env ]]; then
    set -x
    source ${AIRFLOW_SOURCES}/decrypted_variables.env
    set +x
fi

set +a

eval "${@}"
