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

# Airflow requires this variable be set during installation to avoid a GPL
# dependency.
export SLUGIFY_USES_TEXT_UNIDECODE=yes

cd incubator-airflow \
&& pip install -e .[devel,gcp_api,postgres,hive,crypto,celery,rabbitmq] \
&& sudo service postgresql start \
&& sudo -u postgres createuser root \
&& sudo -u postgres createdb airflow/airflow.db

echo
echo "Activating service account with /home/airflow/.key/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
echo

KEY_DIR="/home/airflow/.key"

# gcloud login
if [ -e "/home/airflow/.key/${GCP_SERVICE_ACCOUNT_KEY_NAME}" ]; then
  # Allow application-default login
  echo "export GOOGLE_APPLICATION_CREDENTIALS=${KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" >> /root/.bashrc
  sudo gcloud auth activate-service-account \
       --key-file="${KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
  ACCOUNT=$(cat "${KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" | \
      python -c 'import json, sys; info=json.load(sys.stdin); print info["client_email"]')
  PROJECT=$(cat "${KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME}" | \
      python -c 'import json, sys; info=json.load(sys.stdin); print info["project_id"]')
  gcloud config set account "${ACCOUNT}"
  gcloud config set project "${PROJECT}"
  airflow initdb
  python /home/airflow/_setup_gcp_connection.py "${PROJECT}"
else
  echo "WARNING: No key ${KEY_DIR}/${GCP_SERVICE_ACCOUNT_KEY_NAME} found."\
       " Running without service account credentials."
fi
