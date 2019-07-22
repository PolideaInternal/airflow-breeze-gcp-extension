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
export GCP_PROJECT_ID=${GCP_PROJECT_ID:="no-project-set-please-set-it"}

echo "Removing old DAG links"
echo
rm -rvf ${AIRFLOW_HOME}/dags/*
echo
echo "Removing old logs"
echo
rm -rvf ${AIRFLOW_HOME}/logs/*
echo
echo "Resetting the database"
echo
airflow db reset -y
echo
python ${MY_DIR}/_setup_gcp_connection.py "${GCP_PROJECT_ID}"
echo
source ${MY_DIR}/_create_links.sh
