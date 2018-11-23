#!/usr/bin/env bash
# Copyright 2018 Google LLC #
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
set -euo pipefail

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
AIRFLOW_BREEZE_CONFIG_DIR="${MY_DIR}/airflow-breeze-config"
KEYS_DIR="${AIRFLOW_BREEZE_CONFIG_DIR}/keys"
NOTIFICATIONS_DIR="${AIRFLOW_BREEZE_CONFIG_DIR}/notifications"

pushd ${KEYS_DIR}
for FILE in *.json.enc *.pem.enc
do
  gcloud kms decrypt --plaintext-file $(basename ${FILE} .enc) --ciphertext-file ${FILE} \
     --location=global --keyring=incubator-airflow --key=service_accounts_crypto_key \
     && echo Decrypted ${FILE}
done
chmod -v og-rw *
popd


pushd ${NOTIFICATIONS_DIR}
for FILE in */variables.yaml.enc
do
  gcloud kms decrypt --plaintext-file $(dirname ${FILE})$(basename ${FILE} .enc) \
     --ciphertext-file ${FILE} \
     --location=global --keyring=incubator-airflow --key=service_accounts_crypto_key \
     && echo Decrypted ${FILE}
done
chmod -v og-rw *
popd
