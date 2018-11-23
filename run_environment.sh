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

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Bash sanity settings (error on exit, complain for undefined vars, error when pipe fails)
set -euo pipefail

#################### Default python version

PYTHON_VERSION=2

#################### Whether re-installation should be skipped when entering docker
SKIP_REINSTALL=False

#################### Workspace settings

# Directory where the workspaces are located. For proper usage, this is
# the working directory.
WORKSPACE_DIRECTORY="${MY_DIR}"
# Name of the workspace. If not specified, default is "default".
WORKSPACE_NAME="default"

#################### Dir settings
AIRFLOW_BREEZE_CONFIG_DIR="${MY_DIR}/airflow-breeze-config"
KEYS_DIR="${AIRFLOW_BREEZE_CONFIG_DIR}/keys"

#################### Port forwarding settings

# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""

#################### Build image settings

# If true, the docker image is rebuilt locally. Specified using the -r flag.
REBUILD=false
# Whether to upload image to the GCR Repository
UPLOAD_IMAGE=false
# Repository which is used to clone incubator-airflow from - wh
# en it's not yet checked out
AIRFLOW_REPOSITORY="https://github.com/apache/incubator-airflow.git"
# Branch of the repository to check out when it's first cloned
AIRFLOW_REPOSITORY_BRANCH="master"
# Whether pip install should be executed when entering docker
RUN_PIP_INSTALL=false

#################### Unit test variables

# Holds the test target if the -t flag is used.
DOCKER_TEST_ARG=""

#################### Arbitrary command variable

# Holds arbitrary command if the -x flag is used.
DOCKER_COMMAND_ARG=""

#################### Key variable
# Name of the service account key (should be in the airflow-breeze-config/keys directory)
KEY_NAME="gcp_compute.json"

#################### Helper functions

# Helper function for building the docker image locally.
build_local () {
  echo
  echo "Building docker image '${IMAGE_NAME}'"
  docker build . -t ${IMAGE_NAME}
  if [[ "${UPLOAD_IMAGE}" != "false" ]]; then
    echo
    echo "Uploading built image to ${IMAGE_NAME}"
    echo
    gcloud docker -- push ${IMAGE_NAME}
  fi
}

# Builds a docker run command based on settings and evaluates it.
#
# The workspace is run in an interactive bash session and the incubator-airflow
# directory is mounted as well as key directory for sharing GCP key.
#
# Also becomes superuser within container, installs
# dynamic dependencies, and sets up postgres.
#
# If specified, forwards ports for the webserver.
#
# If performing an unit test run (-t), it is similar to the default run, but immediately
# executes the test(s) specified, then exits.
#
# If performing an integration test run (-i), it is similar to the default run but
# immediately executes integration test(s) specified, then exits.
#
run_container () {
  if [[ ! -z ${DOCKER_TEST_ARG} ]]; then
      echo
      echo "Running CI tests with tests: ${DOCKER_TEST_ARG}"
      echo
      POST_INIT_ARG="/airflow/_run_ci_tests.sh ${DOCKER_TEST_ARG}"
  elif [[ ! -z ${DOCKER_COMMAND_ARG} ]]; then
      echo
      echo "Running arbitrary command: ${DOCKER_COMMAND_ARG}"
      echo
      POST_INIT_ARG="${DOCKER_COMMAND_ARG}"
  else
      POST_INIT_ARG="/bin/bash"
  fi

  #################### Docker command to use
  # String used to build the container run command.
  CMD="""\
docker run --rm -it -v \
  ${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/incubator-airflow:/workspace \
 -v ${WORKSPACE_DIRECTORY}/airflow-breeze-config:/root/airflow-breeze-config \
 -v ${WORKSPACE_DIRECTORY}/output:/airflow/output \
 --env-file=${AIRFLOW_BREEZE_CONFIG_DIR}/decrypted_variables.env \
 -e PYTHON_VERSION=${PYTHON_VERSION} \
 -e SKIP_REINSTALL=${SKIP_REINSTALL} \
 -e AIRFLOW_BREEZE_CONFIG_DIR=/root/airflow-breeze-config \
 -e GCP_SERVICE_ACCOUNT_KEY_NAME=${KEY_NAME} \
 -v ${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/.bash_history:/root/.bash_history \
  ${DOCKER_PORT_ARG} ${IMAGE_NAME} /bin/bash -c \"/airflow/_init.sh ${POST_INIT_ARG}\"
"""

  echo "*************************************************************************"
  echo
  echo
  echo "Docker command to execute: '${CMD}'"
  echo
  echo
  echo "*************************************************************************"
  eval ${CMD}
}

usage() {
      echo
      echo "Usage ./run_environment.sh -a PROJECT_ID [FLAGS] -t <target>"
      echo
      echo "Available general flags:"
      echo
      echo "-h: Show this help message"
      echo "-a: Your GCP Project Id (required)"
      echo "-v: Python version [2, 3]"
      echo "-w: Workspace name [${WORKSPACE_NAME}]"
      echo "-p <port>: Optional - forward the webserver port to <port>"
      echo "-k <key name>: Name of the GCP service account key to use "\
           "(in 'airflow-breeze-config/key' folder) [${KEYS_DIR}] "\
           "- one of:"
      echo "$(cd ${KEYS_DIR} && ls *.json)"
      echo
      echo "Flags for building the docker image locally:"
      echo
      echo "-r: Rebuild the incubator-airflow docker image locally"
      echo "-u: After rebuilding, also send image to GCR repository "\
           " (gcr.io/<PROJECT_ID>/airflow-breeze)"
      echo "-s: Skip reinstalling dependencies in the environment"
      echo "-c: Delete your local copy of the incubator-airflow docker image"
      echo
      echo "Flags for automated checkout of airflow-incubator project:"
      echo
      echo "-R"
      echo "Repository to clone in case the workspace is "\
           "not checked out yet [${AIRFLOW_REPOSITORY}]"
      echo "-B"
      echo "Branch to check out when cloning "\
           "the repository [${AIRFLOW_REPOSITORY_BRANCH}]"
      echo
      echo "Running unit tests:"
      echo
      echo "-t <target>: Run the specified unit test target(s) "
      echo

      echo
      echo "Running arbitrary commands"
      echo
      echo "-x <command>: Run the specified command via bash -c"
      echo

}

decrypt_all_files() {
    echo
    echo "Decrypting all files"
    echo
    ${MY_DIR}/_decrypt_all_files.sh
    echo
    echo "All files decrypted! "
    echo
}

decrypt_all_variables() {
    echo
    echo "Decrypting encrypted variables"
    echo
    (set -a && source "${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env" && set +a && \
     python ${MY_DIR}/_decrypt_encrypted_variables.py> \
          ${AIRFLOW_BREEZE_CONFIG_DIR}/decrypted_variables.env)
    echo
    echo "Variables decrypted! "
    echo
}

####################  Parsing options/arguments

# Parse Flags
while getopts "ha:p:w:uscrIt:k:R:B:v:x:" opt; do
  case ${opt} in
    h)
      usage
      exit 0
      ;;
    a)
      PROJECT_ID="${OPTARG}"
      IMAGE_NAME="gcr.io/${PROJECT_ID}/airflow-breeze"
      ;;
    v)
      PYTHON_VERSION="${OPTARG}"
      ;;
    w)
      WORKSPACE_NAME="${OPTARG}"
      ;;
    u)
      UPLOAD_IMAGE=true
      ;;
    s)
      SKIP_REINSTALL=true
      ;;
    p)
      DOCKER_PORT_ARG="-p 127.0.0.1:${OPTARG}:8080"
      ;;
    :)
      usage
      echo
      echo "ERROR: Option -${OPTARG} requires an argument"
      echo
      exit 1
      ;;
    c)
      if [[ -z "${PROJECT_ID}" ]]; then
        usage
        echo
        echo "ERROR: You need to specify project id with -a before -c is used"
        echo
        exit 1
      fi
      echo "Removing local image..."
      docker rmi ${IMAGE_NAME:-}
      exit 0
      ;;
    r)
      REBUILD=true
      ;;
    R)
      AIRFLOW_REPOSITORY="${OPTARG}"
      ;;
    B)
      AIRFLOW_REPOSITORY_BRANCH="${OPTARG}"
      ;;
    t)
      DOCKER_TEST_ARG="${OPTARG}"
      ;;
    x)
      DOCKER_COMMAND_ARG="${OPTARG}"
      ;;
    k)
      KEY_NAME="${OPTARG:-${KEY_NAME}}"
      ;;
    \?)
      usage
      echo
      echo "ERROR: Unknown option: -${OPTARG}"
      echo
      exit 1
      ;;
  esac
done



#################### Validations

if [[ -z "${PROJECT_ID:-}" ]]; then
  usage
  echo
  echo "ERROR: Missing project id. Specify it with -a <project_id>"
  echo
  exit 1
fi

# Check if the key directory exists
if [[ ! -d ${AIRFLOW_BREEZE_CONFIG_DIR} ]]; then
  echo
  echo "Automatically checking out airflow-breeze-config directory from your Google Project:"
  echo
  gcloud source repos --project ${PROJECT_ID} clone airflow-breeze-config \
    "${AIRFLOW_BREEZE_CONFIG_DIR}" || (\
     echo "You need to have have airflow-breeze-config repository created where you " \
          "should keep your variables and encrypted keys. " \
          "Refer to README for details" && exit 1)
  decrypt_all_files
  decrypt_all_variables
fi

FULL_AIRFLOW_SOURCE_DIR="${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/incubator-airflow"


if [[ ! -f "${KEYS_DIR}/${KEY_NAME}" ]]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "Missing key file ${KEYS_DIR}/${KEY_NAME}"
    echo
    echo "Authentication to Google Cloud Platform will not work."
    echo "You need to place service account json file in key directory if you want"
    echo "to connect to Google Cloud Platform"

    ${MY_DIR}/confirm "Proceeding without key"
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

# Check if the workspace directory exists
if [[ ! -d "${MY_DIR}/${WORKSPACE_NAME}" ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo
  echo "The workspace ${WORKSPACE_NAME} does not exist."
  echo
  echo "Attempting to clone ${AIRFLOW_REPOSITORY} to ${FULL_AIRFLOW_SOURCE_DIR}"
  echo "and checking out ${AIRFLOW_REPOSITORY_BRANCH} branch"
  echo
  ${MY_DIR}/confirm "Cloning the repository"
  echo
  mkdir -p "${FULL_AIRFLOW_SOURCE_DIR}" \
  && chmod 777 "${FULL_AIRFLOW_SOURCE_DIR}" \
  && git clone "${AIRFLOW_REPOSITORY}" "${FULL_AIRFLOW_SOURCE_DIR}" \
  && pushd "${FULL_AIRFLOW_SOURCE_DIR}" \
  && git checkout "${AIRFLOW_REPOSITORY_BRANCH}" \
  && popd
fi

# Check if the .bash_history file exists
if [[ ! -f "${MY_DIR}/${WORKSPACE_NAME}/.bash_history" ]]; then
  echo
  echo "Creating empty .bash_history"
  touch ${MY_DIR}/${WORKSPACE_NAME}/.bash_history
  echo
fi

# Establish an image for the environment
if [[ "${REBUILD}" == "true" ]]; then
  echo
  echo "Rebuilding local image as requested"
  echo
  build_local
elif [[ -z "$(docker images -q "${IMAGE_NAME}" 2> /dev/null)" ]]; then
  echo
  echo "The local image does not exist. Building it"
  echo
  build_local
fi

decrypt_all_files
decrypt_all_variables

echo
echo "Decrypted variables (only visible when you run local environment!):"
echo
cat ${AIRFLOW_BREEZE_CONFIG_DIR}/decrypted_variables.env
echo

echo
echo "*************************************************************************"
echo
echo " Entering airflow development environment in docker"
echo
echo " PYTHON_VERSION      = ${PYTHON_VERSION}"
echo
echo " PROJECT             = ${PROJECT_ID}"
echo
echo " WORKSPACE           = ${WORKSPACE_NAME}"
echo " AIRFLOW_SOURCE_DIR  = ${FULL_AIRFLOW_SOURCE_DIR}"
echo
echo " GCP_SERVICE_KEY     = ${KEY_NAME}"
echo
echo " PORT FORWARDING     = ${DOCKER_PORT_ARG}"
echo
echo "*************************************************************************"

run_container
