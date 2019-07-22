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

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export AIRFLOW_HOME=${AIRFLOW_HOME:=/airflow}
export GCP_CONFIG_DIR=${GCP_CONFIG_DIR:=${HOME}/config}
export GCP_SERVICE_ACCOUNT_KEY_DIR=${GCP_CONFIG_DIR}/keys
export GCP_SERVICE_ACCOUNT_KEY_NAME=${1}
export GCP_PROJECT_ID=${GCP_PROJECT_ID:="no-project-set-please-set-it"}

if [[ ${GCP_SERVICE_ACCOUNT_KEY_NAME} == "" ]]; then
  echo
  echo "WARNING: No key specified"
  echo
  echo "The key should be one of [$(cd ${GCP_SERVICE_ACCOUNT_KEY_DIR} && ls *.json | tr '\n' ',')]."
  echo
  if [[ ${DATABASE_INITIALIZED:=""} == "" ]]; then
      echo
      echo "Resetting the database"
      echo "Works?"
      airflow db reset -y
      echo
      source ${MY_DIR}/_create_links.sh
      echo
  fi
elif [[ -e "${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" ]]; then
  echo
  echo "Activating service account with ${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
  echo
  # Allow application-default login
  echo "export GOOGLE_APPLICATION_CREDENTIALS=${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" >> ${HOME}/.bashrc
  gcloud auth activate-service-account \
       --key-file="${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" \
       --project=${GCP_PROJECT_ID}
  ACCOUNT=$(cat "${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" | \
      python -c 'import json, sys; info=json.load(sys.stdin); print(info["client_email"])')
  echo
  gcloud config set account "${ACCOUNT}"
  gcloud config set project "${GCP_PROJECT_ID}"
  echo
  echo "Removing old DAG links"
  echo
  rm -rvf ${AIRFLOW_HOME}/dags/*
  echo
  echo "Resetting the database"
  echo
  airflow db reset -y
  echo
  python ${MY_DIR}/_setup_gcp_connection.py "${GCP_PROJECT_ID}"
  echo
  source ${MY_DIR}/_create_links.sh
else
  echo
  echo "WARNING: No key ${GCP_SERVICE_ACCOUNT_KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}."
  echo
  echo "The key should be one of [$(cd ${GCP_SERVICE_ACCOUNT_KEY_DIR} && ls *.json | tr '\n' ',')]."
  echo
  if [[ ${DATABASE_INITIALIZED:=""} == "" ]]; then
      echo
      echo "Resetting the database"
      echo
      airflow db reset -y
      echo
      source ${MY_DIR}/_create_links.sh
      echo
  fi
fi

export DATABASE_INITIALIZED=True

echo
echo "You can change the key via 'set_gcp_key KEY_NAME'. "
echo
echo "Running 'set_gcp_key' will show you available keys."
echo
