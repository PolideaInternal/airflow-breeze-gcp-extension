#!/usr/bin/env bash
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
set -euo pipefail

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export AIRFLOW_HOME="${AIRFLOW_HOME:=/airflow}"
export AIRFLOW_ROOT="${AIRFLOW_ROOT:=/workspace}"
export AIRFLOW_OUTPUT="${AIRFLOW_ROOT}/output"
export AIRFLOW_BREEZE_TEST_SUITE="${AIRFLOW_BREEZE_TEST_SUITE:=docs}"
export BUILD_ID="${BUILD_ID:=build}"
export GCP_PROJECT_ID=${GCP_PROJECT_ID:="wrong-project"}

GCP_CONFIG_DIR=${GCP_CONFIG_DIR:=${HOME}/config}
export GCP_SERVICE_ACCOUNT_KEY_DIR=${GCP_CONFIG_DIR}/keys

# Create logs dir preemptively - if same directory is created in parallel in two
# images, one of the newly created dirs might disappear - it's likely due to the way
# syncing the volume data back works
export LOG_OUTPUT_DIR=${AIRFLOW_OUTPUT}/${BUILD_ID}/logs/
mkdir -pv ${LOG_OUTPUT_DIR}

echo "Decrypting variables"
bash ${AIRFLOW_HOME}/_decrypt_encrypted_variables.sh ${GCP_PROJECT_ID} \
   > ${AIRFLOW_ROOT}/decrypted_variables.env
echo "Decrypted variables. Number of variables decrypted: "\
     "$(wc -l ${AIRFLOW_ROOT}/decrypted_variables.env)"

echo "Decrypting keys from ${GCP_SERVICE_ACCOUNT_KEY_DIR}"
pushd ${GCP_SERVICE_ACCOUNT_KEY_DIR}
for FILE in *.json.enc *.pem.enc;
do
  gcloud kms decrypt --plaintext-file $(basename ${FILE} .enc) --ciphertext-file ${FILE} \
     --location=global --keyring=airflow --key=airflow_crypto_key \
     --project=${GCP_PROJECT_ID}\
     && echo Decrypted ${FILE}
done
chmod -v og-rw *
popd
