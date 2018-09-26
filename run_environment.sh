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

#################### Workspace settings

# Directory where the workspaces are located. For proper usage, this is
# the working directory.
WORKSPACE_DIRECTORY="${MY_DIR}"
# Name of the workspace. If not specified, default is "default".
WORKSPACE_NAME="default"


#################### Port forwarding settings

# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""


#################### Build image settings

# If true, the docker image is rebuilt locally. Specified using the -r flag.
REBUILD=false
# Whether to upload image to the GCR Repository
UPLOAD_IMAGE=false
# Repository which is used to clone incubator-airflow from - when it's not yet checked out
AIRFLOW_REPOSITORY="https://github.com/apache/incubator-airflow.git"
# Branch of the repository to check out when it's first cloned
AIRFLOW_REPOSITORY_BRANCH="master"
# Whether pip install should be executed when entering docker
RUN_PIP_INSTALL=false

#################### Unit test variables

# Holds the test target if the -t flag is used.
DOCKER_TEST_ARG=""


#################### Integration test variables

# Dags specification for integration tests
INT_TEST_DAGS=""
# Comma-separated key-value pairs of variables passed to the container,
# transformed internally into Airflow variables necessary for integration tests
INT_TEST_VARS=""
# Name of the service account key (should be in the 'key' directory)
GCP_SERVICE_ACCOUNT_KEY_NAME="key.json"

#################### Docker command to use

# String used to build the container run command.
DOCKER_COMMAND_FORMAT_STRING=''\
'docker run --rm -it '\
'-v %s/incubator-airflow:/home/airflow/incubator-airflow '\
'-v %s/key:/home/airflow/.key '\
'-v %s/.bash_history:/root/.bash_history '\
'-e GCP_SERVICE_ACCOUNT_KEY_NAME '\
'-u airflow %s %s '\
'bash -c "sudo -E ./_init.sh && cd incubator-airflow && sudo -E su%s'

#################### Helper functions

# Helper function for building the docker image locally.
build_local () {
  echo
  echo "Building docker image '${IMAGE_NAME}'"
  docker build . -t ${IMAGE_NAME}
  if [ "${UPLOAD_IMAGE}" != "false" ]; then
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
      echo "Running unit tests with tests: ${DOCKER_TEST_ARG}"
      echo
      POST_INIT_ARG=" -c './run_unit_tests.sh '${DOCKER_TEST_ARG}' "\
                    " -s --logging-level=DEBUG'\""
  elif [[ ! -z ${INT_TEST_DAGS} ]]; then
      echo
      echo "Running integration tests with variables: ${INT_TEST_VARS} and "\
           " dags: ${INT_TEST_DAGS}"
      echo
      POST_INIT_ARG=" -c './run_int_tests.sh --vars='${INT_TEST_VARS}'"\
                    " --dags='${FULL_AIRFLOW_SOURCE_DIR}/${INT_TEST_DAGS}'\""
  else
      POST_INIT_ARG="\""
  fi

  export GCP_SERVICE_ACCOUNT_KEY_NAME

  CMD=$(printf "${DOCKER_COMMAND_FORMAT_STRING}" \
               "${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}" \
               "${WORKSPACE_DIRECTORY}" \
               "${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}" \
               "${DOCKER_PORT_ARG}" \
               "${IMAGE_NAME}" \
               "${POST_INIT_ARG}")
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
      echo "Usage ./run_environment.sh -a PROJECT_ID "\
           "[FLAGS] [-t <target> |-i <dag_path>] "
      echo
      echo "Available general flags:"
      echo
      echo "-h: Show this help message"
      echo "-a: Your GCP Project Id (required)"
      echo "-w: Workspace name [${WORKSPACE_NAME}]"
      echo "-p <port>: Optional - forward the webserver port to <port>"
      echo "-k <key name>: Name of the GCP service account key to use "\
           "(in 'key' folder) [${GCP_SERVICE_ACCOUNT_KEY_NAME}]"
      echo
      echo "Flags for building the docker image locally:"
      echo
      echo "-r: Rebuild the incubator-airflow docker image locally"
      echo "-u: After rebuilding, also send image to GCR repository "\
           " (gcr.io/<PROJECT_ID>/airflow-upstream)"
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
      echo "Running integration tests:"
      echo
      echo "-i <path>: Run integration test DAGs from the specified path "\
           "relative to incubator-airflow directory"\
           "e.g. \"airflow/contrib/example_dags/\*\""
      echo "-e <key-value pairs>: Pass Airflow Variables to integration tests"\
           " as an array of coma-separated key-value pairs "\
           "e.g. [KEY1=VALUE1,KEY2=VALUE2,...]"
      echo

}

####################  Parsing options/arguments

# Parse Flags
while getopts "ha:p:w:ucrIt:e:i:k:R:B:" opt; do
  case ${opt} in
    h)
      usage
      exit 0
      ;;
    a)
      PROJECT_ID="${OPTARG}"
      IMAGE_NAME="gcr.io/${PROJECT_ID}/airflow-upstream"
      ;;
    w)
      WORKSPACE_NAME="${OPTARG}"
      ;;
    u)
      UPLOAD_IMAGE=true
      ;;
    p)
      DOCKER_PORT_ARG="-p 127.0.0.1:${OPTARG}:8080"
      ;;
    e)
      INT_TEST_VARS="${OPTARG}"
      ;;
    :)
      usage
      echo
      echo "ERROR: Option -${OPTARG} requires an argument"
      echo
      exit 1
      ;;
    c)
      if [ -z "${PROJECT_ID}" ]; then
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
    i)
      INT_TEST_DAGS="${OPTARG}"
      ;;
    k)
      GCP_SERVICE_ACCOUNT_KEY_NAME="${OPTARG:-${GCP_SERVICE_ACCOUNT_KEY_NAME}}"
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

if [ -z "${PROJECT_ID:-}" ]; then
  usage
  echo
  echo "ERROR: Missing project id. Specify it with -a <project_id>"
  echo
  exit 1
fi

# Check if the key directory exists
if [ ! -d "key" ]; then
  echo
  echo "Automatically creating key directory:"
  mkdir -v ${MY_DIR}/key
  echo
fi

FULL_AIRFLOW_SOURCE_DIR="${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/incubator-airflow"

if [ ! -f "${MY_DIR}/key/${GCP_SERVICE_ACCOUNT_KEY_NAME}" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "Missing key file ${MY_DIR}/key/${GCP_SERVICE_ACCOUNT_KEY_NAME}"
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
if [ ! -f "${MY_DIR}/${WORKSPACE_NAME}/.bash_history" ]; then
  echo
  echo "Creating empty .bash_history"
  touch ${MY_DIR}/${WORKSPACE_NAME}/.bash_history
  echo
fi


# Establish an image for the environment
if [ "${REBUILD}" == "true" ]; then
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

echo "**************************************************************"
echo
echo " Entering airflow development environment in docker"
echo
echo " PROJECT             = ${PROJECT_ID}"
echo
echo " WORKSPACE           = ${WORKSPACE_NAME}"
echo " AIRFLOW_SOURCE_DIR  = ${FULL_AIRFLOW_SOURCE_DIR}"
echo
echo " GCP_SERVICE_KEY     = ${GCP_SERVICE_ACCOUNT_KEY_NAME}"
echo
echo " PORT FORWARDING     = ${DOCKER_PORT_ARG}"
echo
echo "**************************************************************"

run_container