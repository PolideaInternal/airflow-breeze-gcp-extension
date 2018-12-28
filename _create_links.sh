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

AIRFLOW_BREEZE_DAGS_TO_TEST=${AIRFLOW_BREEZE_DAGS_TO_TEST:=""}
AIRFLOW_HOME=${AIRFLOW_HOME:=/airflow}
AIRFLOW_SOURCES="${AIRFLOW_SOURCES:=/workspace}"

if [[ ! -z ${AIRFLOW_BREEZE_DAGS_TO_TEST} ]]; then
    echo
    echo "Creating symbolic links to tested DAGs"
    echo

    for DAG_TO_TEST in ${AIRFLOW_BREEZE_DAGS_TO_TEST}
    do
         for FILE in $(ls ${AIRFLOW_SOURCES}/${DAG_TO_TEST})
         do
            FILE_BASENAME=$(basename ${FILE})
            ln -svf "${FILE}" "${AIRFLOW_HOME}"/dags/${FILE_BASENAME}
         done
    done
fi
