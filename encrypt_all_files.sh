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
set -euo pipefail

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#################### Workspace name #######################################################
export AIRFLOW_BREEZE_WORKSPACE_FILE=${MY_DIR}/.workspace

if [[ -z ${AIRFLOW_BREEZE_WORKSPACE_NAME:=""} && ! -f ${AIRFLOW_BREEZE_WORKSPACE_FILE} ]]; then
    echo "Run ./run_environment.sh to choose the default workspace"
    exit 1
fi

export AIRFLOW_BREEZE_WORKSPACE_NAME="${AIRFLOW_BREEZE_WORKSPACE_NAME:=$(cat ${AIRFLOW_BREEZE_WORKSPACE_FILE} 2>/dev/null)}"

#################### Directories #######################################################

export AIRFLOW_BREEZE_CONFIG_DIR="${AIRFLOW_BREEZE_CONFIG_DIR:=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/airflow-breeze-config}"
export AIRFLOW_BREEZE_KEYS_DIR="${AIRFLOW_BREEZE_KEYS_DIR:=${AIRFLOW_BREEZE_CONFIG_DIR}/keys}"
export AIRFLOW_BREEZE_NOTIFICATIONS_DIR="${AIRFLOW_BREEZE_NOTIFICATIONS_DIR:=${AIRFLOW_BREEZE_CONFIG_DIR}/notifications}"
export AIRFLOW_BREEZE_PROJECT_ID_FILE=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.project_id
export AIRFLOW_BREEZE_PROJECT_ID=${AIRFLOW_BREEZE_PROJECT_ID:-}

if [[ -z "${AIRFLOW_BREEZE_PROJECT_ID}" ]]; then
  if [[ -f ${AIRFLOW_BREEZE_PROJECT_ID_FILE} ]]; then
     export AIRFLOW_BREEZE_PROJECT_ID=$(cat ${AIRFLOW_BREEZE_PROJECT_ID_FILE})
  else
    echo
    echo "ERROR: Missing project id."
    echo
    exit 1
  fi
fi


pushd ${AIRFLOW_BREEZE_KEYS_DIR}
FILES=$(ls *.json *.pem 2>/dev/null || true)
for FILE in ${FILES}
do
  gcloud kms encrypt --plaintext-file ${FILE} --ciphertext-file ${FILE}.enc \
     --location=global --keyring=incubator-airflow --key=service_accounts_crypto_key \
     --project=${AIRFLOW_BREEZE_PROJECT_ID} \
     && echo Encrypted ${FILE}
done
popd

pushd ${AIRFLOW_BREEZE_NOTIFICATIONS_DIR}
FILES=$(ls */secret.variables.yaml 2>/dev/null || true)
for FILE in ${FILES}
do
  gcloud kms encrypt --plaintext-file ${FILE} --ciphertext-file ${FILE}.enc \
     --location=global --keyring=incubator-airflow --key=service_accounts_crypto_key \
     --project=${AIRFLOW_BREEZE_PROJECT_ID} \
     && echo Encrypted ${FILE}
done

