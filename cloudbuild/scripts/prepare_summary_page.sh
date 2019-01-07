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
set -x

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export AIRFLOW_HOME="${AIRFLOW_HOME:=/airflow}"
export AIRFLOW_SOURCES="${AIRFLOW_SOURCES:=/workspace}"
export AIRFLOW_OUTPUT="${AIRFLOW_SOURCES}/output"
export BUILD_ID="${BUILD_ID:=build}"
export GCP_PROJECT_ID="${GCP_PROJECT_ID:=example-project}"
export AIRFLOW_BREEZE_GCP_BUILD_BUCKET="${AIRFLOW_BREEZE_GCP_BUILD_BUCKET:=example-bucket}"
export HTML_OUTPUT_DIR=${AIRFLOW_OUTPUT}/${BUILD_ID}
export AIRFLOW_BREEZE_TEST_SUITES="${AIRFLOW_BREEZE_TEST_SUITES:=python2}"
export AIRFLOW_BREEZE_GITHUB_ORGANIZATION=${AIRFLOW_BREEZE_GITHUB_ORGANIZATION:=apache}
export AIRFLOW_REPO_NAME=${AIRFLOW_REPO_NAME:=airflow}

export TEST_OUTPUT_DIR=${AIRFLOW_OUTPUT}/${BUILD_ID}/tests

export AIRFLOW_REPO_NAME=${AIRFLOW_REPO_NAME:-""}
export TAG_NAME=${TAG_NAME:-""}
export BRANCH_NAME=${BRANCH_NAME:-""}
export COMMIT_SHA=${COMMIT_SHA:-""}

TEST_ENV_SUMMARY=""

FAILED="false"

for AIRFLOW_BREEZE_TEST_SUITE in ${AIRFLOW_BREEZE_TEST_SUITES}
do
    ENVIRONMENT_STATUS="<font color=\"green\">Passed</font>"
    set +e
    ls ${TEST_OUTPUT_DIR}/${AIRFLOW_BREEZE_TEST_SUITE}-*-failure.txt
    FAILURE_FILES_EXIST=$?
    set -e
    if [[ "${FAILURE_FILES_EXIST}" == "0" ]]; then
        ENVIRONMENT_STATUS="<font color=\"red\">Failed!</font>"
        FAILED="true"
    fi
    TEST_ENV_SUMMARY="""${TEST_ENV_SUMMARY}
                       <li><a href=\"https://storage.googleapis.com/${AIRFLOW_BREEZE_GCP_BUILD_BUCKET}/${BUILD_ID}/tests/${AIRFLOW_BREEZE_TEST_SUITE}.xml.html\">
 ${AIRFLOW_BREEZE_TEST_SUITE} test results</a>:  ${ENVIRONMENT_STATUS}</li>
"""
done

STATUS="Overall status: <font color=\"green\">Passed!</font>"

if [[ ${FAILED} == "true" ]]; then
    STATUS="Overall status: <font color=\"red\">Failed!</font>"
fi

export GITHUB_COMMIT_API_URL=https://api.github.com/repos/${AIRFLOW_BREEZE_GITHUB_ORGANIZATION}/${AIRFLOW_REPO_NAME}/commits/${COMMIT_SHA}
curl -s ${GITHUB_COMMIT_API_URL} >/tmp/commit.json
export COMMIT_MESSAGE=$(cat /tmp/commit.json | jq -r ".commit.message" | head -n 1)
export COMMITTER=$(cat /tmp/commit.json | jq -r ".commit.committer.name")
export AUTHOR=$(cat /tmp/commit.json | jq -r ".commit.author.name")

export CURRENT_DATE=$(date)

export HTML_CONTENT="""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">

  <title>Summary page for the ${AIRFLOW_REPO_NAME} ${BRANCH_NAME} build ${BUILD_ID} in project ${GCP_PROJECT_ID}</title>
  <meta name=\"description\" content=\"Summary page for the ${AIRFLOW_REPO_NAME} ${BRANCH_NAME} build ${BUILD_ID}\">

</head>

    <body>

          <h1>${AIRFLOW_REPO_NAME}[${BRANCH_NAME}] - ${CURRENT_DATE}</h1>
          <h2>${STATUS}</h2>
          <h2>Build info:</h2>
          <ul>
              <li>GCP project id: ${GCP_PROJECT_ID}</li>
              <li>Build id: ${BUILD_ID}</li>
              <li>Build time and date: ${CURRENT_DATE}</li>
              <li>Branch name: ${BRANCH_NAME}</li>
              <li>Tag name: ${TAG_NAME}</li>
              <li>Commit SHA: ${COMMIT_SHA}</li>
              <li>Commit message: ${COMMIT_MESSAGE}</li>
              <li>Committer: ${COMMITTER}</li>
              <li>Author: ${AUTHOR}</li>
         </ul>
          <h2>Links:</h2>
          <ul>
            <li><a href=\"https://console.cloud.google.com/cloud-build/builds/${BUILD_ID}?project=${GCP_PROJECT_ID}\">Google Cloud Build</a></li>
            <li><a href=\"https://console.cloud.google.com/storage/browser/${AIRFLOW_BREEZE_GCP_BUILD_BUCKET}/${BUILD_ID}/logs/?project=${GCP_PROJECT_ID}\">Task logs in GCS bucket</a></li>
            <li><a href=\"https://console.cloud.google.com/logs/viewer?authuser=0&project=${GCP_PROJECT_ID}&minLogLevel=0&expandAll=false&resource=build%2Fbuild_id%2F${BUILD_ID}\">Stackdriver logs</a></li>
            <li><a href=\"https://storage.googleapis.com/${AIRFLOW_BREEZE_GCP_BUILD_BUCKET}/${BUILD_ID}/docs/index.html\">Generated documentation</a></li>
            <li>Branch: <a href=\"https://github.com/${AIRFLOW_BREEZE_GITHUB_ORGANIZATION}/${AIRFLOW_REPO_NAME}/tree/${BRANCH_NAME}\">GitHub ${AIRFLOW_REPO_NAME}: ${BRANCH_NAME}</a></li>
            <li>Commit: <a href=\"https://github.com/${AIRFLOW_BREEZE_GITHUB_ORGANIZATION}/${AIRFLOW_REPO_NAME}/commit/${COMMIT_SHA}\">${COMMIT_MESSAGE}</a></li>
            ${TEST_ENV_SUMMARY}
            <li><a href=\"https://storage.googleapis.com/${AIRFLOW_BREEZE_GCP_BUILD_BUCKET}/${BUILD_ID}/build_resource.json\">Build Resource (for Cloud Function Triggering)</a></li>
          </ul>
    </body>
</html>
"""

echo "${HTML_CONTENT}" > ${HTML_OUTPUT_DIR}/index.html
