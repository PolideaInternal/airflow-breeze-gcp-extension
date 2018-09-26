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


# Directory where the workspaces are located. For proper usage, this is
# the working directory.
WORKSPACE_DIRECTORY="$(pwd)"
# Name of the workspace. If not specified, default is "default".
WORKSPACE_NAME="default"
# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""
# Holds the test target if the -t flag is used.
DOCKER_TEST_ARG="" # The tag of the docker image for running a workspace.
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
'-e GCP_SERVICE_ACCOUNT_KEY_NAME '\
'-u airflow %s %s '\
'bash -c "sudo -E ./_init.sh && cd incubator-airflow && sudo -E su%s'

# Helper function for building the docker image locally.
build_local () {
  docker build . -t ${IMAGE_NAME}
  gcloud docker -- push ${IMAGE_NAME}
}

# Builds a docker run command based on settings and evaluates it.
# The workspace is run in an interactive bash session and the incubator-airflow
# directory is mounted. Also becomes superuser within container, installs
# dynamic dependencies, and sets up postgres. If specified, forwards ports for
# the webserver. If performing a test run, it is similar to the default run,
# but immediately executes a test, then exits.
run_container () {
  if [[ ! -z ${DOCKER_TEST_ARG} ]]; then
      POST_INIT_ARG=" -c './run_unit_tests.sh '"${DOCKER_TEST_ARG}"' \
      -s --logging-level=DEBUG'\""
  elif [[ ! -z ${DAGS_PATH} ]]; then
      POST_INIT_ARG=" -c './run_int_tests.sh --vars="${DOCKER_ENV_ARGS}" --dags="${DAGS_PATH}"'\""
  else
      POST_INIT_ARG="\""
  fi
  CMD=$(printf "${FORMAT_STRING}" "${WORKSPACE_DIRECTORY}" "${WORKSPACE_NAME}" "${WORKSPACE_DIRECTORY}" "${DOCKER_PORT_ARG}" "${IMAGE_NAME}" "${POST_INIT_ARG}")
  echo ${CMD}
  eval ${CMD}
}

# Parse Flags
while getopts "ha:p:w:uct:e:i:k" opt; do
  case ${opt} in
    h)
      echo "Usage ./run_environment.sh -a PROJECT_ID"
      echo "FLAGS"
      echo "-a"
      echo "Your GCP Project Id (required)"
      echo "-w"
      echo "Workspace name (ex: update_dataproc)"
      echo "-h"
      echo "Show this help message"
      echo "-p <port>"
      echo "Forward the webserver port to <port>"
      echo "-e <key-value pairs>"
      echo "Pass Airflow variables as an array of comma-separated key-value pairs" \
           "e.g. [KEY1=VALUE1,KEY2=VALUE2,...]"
      echo "-c"
      echo "Delete your local copy of the environment image"
      echo "-r"
      echo "Rebuild the environment image locally"
      echo "-t <target>"
      echo "Run the specified unit test target"
      echo "-i <path>"
      echo "Run integration test DAGs from the specified path, e.g. " \
           "/home/airflow/incubator-airflow/airflow/contrib/example_dags/*"
      exit 0
      ;;
    a)
      PROJECT_ID="${OPTARG}"
      ;;
    w)
      WORKSPACE_NAME="${OPTARG}"
      ;;
    p)
      DOCKER_PORT_ARG="-p 127.0.0.1:${OPTARG}:8080"
      ;;
    e)
      DOCKER_ENV_ARGS="${OPTARG}"
      ;;
    :)
      echo "Option -${OPTARG} requires an argument"
      exit 1
      ;;
     c)
      echo "Removing local image..."
      docker rmi ${IMAGE_NAME}
      exit 0
      ;;
     r)
      REBUILD=true
      ;;
     t)
      DOCKER_TEST_ARG="${OPTARG}"
      ;;
    k)
      GCP_SERVICE_ACCOUNT_KEY_NAME="${OPTARG:-${GCP_SERVICE_ACCOUNT_KEY_NAME}}"
      ;;
    \?)
      echo "Unknown option: -${OPTARG}"
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  echo "Missing project ID arg."
  exit 1
fi
IMAGE_NAME="gcr.io/${PROJECT_ID}/airflow-upstream"

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
fi

# Check if the workspace is already made
if [[ ! -d "$WORKSPACE_NAME" ]]; then
  mkdir -p "${WORKSPACE_NAME}/incubator-airflow" \
  && chmod 777 ${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/incubator-airflow \
  && git clone https://github.com/apache/incubator-airflow.git "${WORKSPACE_NAME}/incubator-airflow"
fi

# Establish an image for the environment
if ${REBUILD}; then
  build_local
elif [[ -z "$(docker images -q ${IMAGE_NAME} 2> /dev/null)" ]]; then
  build_local
fi

run_container
