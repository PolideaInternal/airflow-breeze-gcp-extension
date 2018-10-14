#!/usr/bin/env bash
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

# cd, install from source, and setup postgres

# Make sure all environment variables created below are exported
# even if they are not explicitly exported (just in case)

. /usr/share/virtualenvwrapper/virtualenvwrapper.sh

set -euo pipefail

# Automatically export all variables
set -a

# Airflow requires this variable be set during installation to avoid a GPL
# dependency.
export SLUGIFY_USES_TEXT_UNIDECODE=yes
export AIRFLOW_HOME=${AIRFLOW_HOME:=/airflow}

AIRFLOW_BREEZE_CONFIG_DIR="${HOME}/airflow-breeze-config"
if [[ -f ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env ]]; then
  echo "Sourcing variables from ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env"
  set -x
  source ${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env
  set +x
fi

PYTHON_VERSION=${PYTHON_VERSION:=2}

if [[ "${PYTHON_VERSION}" = "2" ]]; then
  echo "Python 2.7 used"
  echo
  set +ue
  workon airflow27
  set -ue
else
  echo
  echo "Python 3.5 used"
  echo
  set +ue
  workon airflow35
  set -ue
fi

cd /workspace

pip install -e .[devel_ci] \
  && sudo service postgresql start \
  && sudo -u postgres createuser root \
  && sudo -u postgres createdb airflow/airflow.db
export AIRFLOW_BREEZE_CONFIG_DIR=${AIRFLOW_BREEZE_CONFIG_DIR:=/root/airflow-breeze-config}
export GCP_SERVICE_ACCOUNT_KEY_DIR=${AIRFLOW_BREEZE_CONFIG_DIR}/keys
export GCP_SERVICE_ACCOUNT_KEY_NAME=${GCP_SERVICE_ACCOUNT_KEY_NAME:="gcp_compute.json"}
echo
echo "Activating service account with ${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
echo

# gcloud login
if [[ -e "${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" ]]; then
  # Allow application-default login
  echo "export GOOGLE_APPLICATION_CREDENTIALS=${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" >> ${HOME}/.bashrc
  gcloud auth activate-service-account \
       --key-file="${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
  ACCOUNT=$(cat "${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" | \
      python -c 'import json, sys; info=json.load(sys.stdin); print(info["client_email"])')
  PROJECT=$(cat "${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" | \
      python -c 'import json, sys; info=json.load(sys.stdin); print(info["project_id"])')
  gcloud config set account "${ACCOUNT}"
  gcloud config set project "${PROJECT}"
  airflow initdb
  python /airflow/_setup_gcp_connection.py "${PROJECT}"
else
  echo "WARNING: No key ${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME} found."\
       " Running without service account credentials."
fi

AIRFLOW_SOURCES="${AIRFLOW_SOURCES:=/workspace}"

if [[ -f ${AIRFLOW_SOURCES}/decrypted_variables.env ]]; then
    source ${AIRFLOW_SOURCES}/decrypted_variables.env
fi

set +a

DAGS_TO_TEST=${DAGS_TO_TEST:=""}

if [[ ! -z ${DAGS_TO_TEST} ]]; then
    echo
    echo "Creating symbolic links to tested DAGs"
    echo

    for DAG_TO_TEST in ${DAGS_TO_TEST}
    do
         for FILE in $(ls ${AIRFLOW_SOURCES}/${DAG_TO_TEST})
         do
            FILE_BASENAME=$(basename $FILE)
            ln -svf "${FILE}" "${AIRFLOW_HOME}"/dags/${FILE_BASENAME}
         done
    done

fi


eval "${@}"