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

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Bash sanity settings (error on exit, complain for undefined vars, error when pipe fails)
set -euo pipefail

CMDNAME="$(basename -- "$0")"

#################### Default python version

PYTHON_VERSION=2.7
APACHE_AIRFLOW_REPO=https://github.com/apache/incubator-airflow.git
AIRFLOW_BREEZE_REPO=https://github.com/PolideaInternal/airflow-breeze

#################### Whether re-installation should be skipped when entering docker
SKIP_REINSTALL=False

#################### Port forwarding settings
# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""

#################### Build image settings

# If true, the docker image is rebuilt locally. Specified using the -r flag.
REBUILD=false
# Whether to upload image to the GCR Repository
UPLOAD_IMAGE=false
# Whether to download image to the GCR Repository
DOWNLOAD_IMAGE=false
# Whether to cleanup local image
CLEANUP_IMAGE=false
# Whether to list keys
LIST_KEYS=false
# Repository which is used to clone incubator-airflow from - wh
# en it's not yet checked out (default is the Apache one)

AIRFLOW_REPOSITORY=""
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


#################### Reconfigure the GCP project
RECONFIGURE_GCP_PROJECT=false

#################### Recreate the GCP project
RECREATE_GCP_PROJECT=false

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
    docker push ${IMAGE_NAME}
  fi
}
# Helper function for building the docker image locally.
download () {
  echo
  echo "Download docker image '${IMAGE_NAME}'"
  docker pull ${IMAGE_NAME}
}

cleanup () {
  echo "Removing local image ${IMAGE_NAME} ..."
  docker rmi ${IMAGE_NAME}
  exit 0
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
docker run --rm -it --name airflow-breeze-${AIRFLOW_BREEZE_WORKSPACE_NAME} \
 -v ${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}:/workspace \
 -v ${AIRFLOW_BREEZE_OUTPUT_DIR}:/airflow/output \
 -v ${AIRFLOW_BREEZE_CONFIG_DIR}:/root/airflow-breeze-config \
 --env-file=${AIRFLOW_BREEZE_CONFIG_DIR}/decrypted_variables.env \
 -e PYTHON_VERSION=${PYTHON_VERSION} \
 -e SKIP_REINSTALL=${SKIP_REINSTALL} \
 -e AIRFLOW_BREEZE_CONFIG_DIR=/root/airflow-breeze-config \
 -e GCP_SERVICE_ACCOUNT_KEY_NAME=${AIRFLOW_BREEZE_KEY_NAME} \
 -v ${AIRFLOW_BREEZE_BASH_HISTORY_FILE}:/root/.bash_history \
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
      echo """

Usage ${CMDNAME} [FLAGS] [-t <TEST_TARGET | -x <COMMAND ]

Flags:

-h, --help
        Shows this help message.

-p, --project <GCP_PROJECT_ID>
        Your GCP Project Id (required for the first time). Cached between runs.

-w, --workspace <WORKSPACE>
        Workspace name [default]. Folder with this name is created and sources
        are downloaded automatically if it does not exist. Cached between runs. [default]

-k, --key-name <KEY_NAME>
        Name of the GCP service account key to use by default. Keys are stored in
        '<WORKSPACE>/airflow-breeze-config/key' folder. Cached between runs. If not
        specified, you need to confirm that you want to enter the environment without
        the key. You can also switch keys manually after entering the environment
        via 'gcloud auth activate-service-account /root/airflow-breeze-config/keys/<KEY>'.

-K, --key-list
        List all service keys that can be used with --key-name flag.

-P, --python <PYTHON_VERSION>
        Python virtualenv used by default. One of ('2.7', '3.5', '3.6'). [2.7]

-f, --forward-port <PORT_NUMBER>
        Optional - forward the port PORT_NUMBER to airflow's webserver (you must start
        the server with 'airflow webserver' command manually).

Reconfiguring existing project:

-g, --reconfigure-gcp-project
        Reconfigures the project already present in the workspace.
        It adds all new variables in case they were added, creates new service accounts
        and updates to latest version of the notification cloud functions if they are used.

-G, --recreate-gcp-project
        Reconfigures the project already present in the workspace but recreates
        all sensitive data - it creates new service accounts, generates new
        service account keys, regenerates passwords, recreates bucket. It also performs
        all actions done by reconfigure project.

Managing the docker image of airflow-breeze:

-r, --rebuild-image
        Rebuild the incubator-airflow docker image locally

-u, --upload-image
        After rebuilding, also upload the image to GCR repository
        (gcr.io/<GCP_PROJECT_ID>/airflow-breeze). Needs GCP_PROJECT_ID.

-d, --download-image
        Downloads the image from GCR repository (gcr.io/<GCP_PROJECT_ID>/airflow-breeze)
        rather than build it locally. Needs GCP_PROJECT_ID.

-c, --cleanup-image
        Clean your local copy of the incubator-airflow docker image.
        Needs GCP_PROJECT_ID.


Automated checkout of airflow-incubator project:

-R, --repository [REPOSITORY]
        Repository to clone in case the workspace is not checked out yet
        [${AIRFLOW_REPOSITORY}].
-B, --branch [BRANCH]
        Branch to check out when cloning the repository specified by -R. [master]


Optional unit tests execution (mutually exclusive with running arbitrary command):

-t, --test-target <TARGET>
        Run the specified unit test target. There might be multiple
        targets specified.



Optional arbitrary command execution (mutually exclusive with running tests):

-x, --execute <COMMAND>
        Run the specified command. It is run via 'bash -c' so if you want to run command
        with parameters they must be all passed as one COMMAND (enclosed with ' or \".


"""
}
####################  Parsing options/arguments

set +e
getopt -T
GETOPT_RETVAL=$?
set -e

if [[ ${GETOPT_RETVAL} != 4 ]]; then
    echo
    if [[ $(uname -s) == 'Darwin' ]] ; then
        echo "You are running ${CMDNAME} in OSX environment"
        echo "The getopt version installed by OSX should be replaced by the GNU one"
        echo
        echo "Run 'brew install gnu-getopt'"
        echo
        echo "And link it to become default as suggested by brew by typing:"
        echo "echo 'export PATH=\"/usr/local/opt/gnu-getopt/bin:\$PATH\"' >> ~/.bash_profile"
        echo ". ~/.bash_profile"
    else
        echo "You do not have enhanced version of getopt binary in the path."
        echo "Please install latest/GNU version."
    fi
    echo
    exit 1
fi

PARAMS=$(getopt \
    -o hp:w:k:KP:f:rudcgGR:B:t:x: \
    -l help,project:,workspace:,key-name:,key-list,python:,forward-port:,rebuild-image,upload-image,dowload-image,cleanup-image,reconfigure-gcp-project,recreate-gcp-project,repository:,branch:,test-target:,execute: \
    --name "$CMDNAME" -- "$@")

if [[ $? -ne 0 ]]
then
    usage
fi

eval set -- "${PARAMS}"
unset PARAMS

# Parse Flags
while true
do
  case "${1}" in
    -h|--help)
      usage; exit 0 ;;
    -p|--project)
      AIRFLOW_BREEZE_PROJECT_ID="${2}"; shift 2 ;;
    -w|--workspace)
      AIRFLOW_BREEZE_WORKSPACE_NAME="${2}"; shift 2 ;;
    -k|--key-name)
      AIRFLOW_BREEZE_KEY_NAME="${2}"; shift 2 ;;
    -K|--key-list)
      LIST_KEYS="true"; shift ;;
    -P|--python)
      PYTHON_VERSION="${2}"; shift 2 ;;
    -f|--forward-port)
      DOCKER_PORT_ARG="-p 127.0.0.1:${2}:8080"; shift 2 ;;
    -r|--rebuild-image)
      REBUILD=true; shift ;;
    -u|--upload-image)
      UPLOAD_IMAGE=true
      if [[ ! ${DOWNLOAD_IMAGE} != "false" || ${CLEANUP_IMAGE} != "false" ]]; then
         echo "Cannot specify two of 'upload', 'download' or 'cleanup' at the same time"
         exit 1
      fi
      shift ;;
    -d|--download-image)
      DOWNLOAD_IMAGE=true
      if [[ ${UPLOAD_IMAGE} != "false" || ${CLEANUP_IMAGE} != "false" ]]; then
         echo "Cannot specify two of 'upload', 'download', 'cleanup' at the same time"
         exit 1
      fi
      shift ;;
    -c|--cleanup-image)
      if [[ ${UPLOAD_IMAGE} != "false" || ${DOWNLOAD_IMAGE} != "false" ]]; then
         echo "Cannot specify two of 'upload', 'download', 'cleanup' at the same time"
         exit 1
      fi
      CLEANUP_IMAGE=true
      shift ;;
    -g|--reconfigure-gcp-project)
      RECONFIGURE_GCP_PROJECT=true; shift ;;
    -G|--recreate-gcp-project)
      RECREATE_GCP_PROJECT=true; shift ;;
    -R|--repository)
      AIRFLOW_REPOSITORY="${2}"; shift 2 ;;
    -B|--branch)
      AIRFLOW_REPOSITORY_BRANCH="${2}"; shift 2 ;;
    -t|--test-target)
      DOCKER_TEST_ARG="${2}"; shift 2 ;;
    -x|--execute)
      DOCKER_COMMAND_ARG="${2}"; shift 2 ;;
    --) shift ; break ;;
    *)
      usage
      echo
      echo "ERROR: Unknown argument ${1}"
      echo
      exit 1
      ;;
  esac
done


#################### Workspace name #######################################################
export AIRFLOW_BREEZE_WORKSPACE_FILE=${MY_DIR}/.workspace

export AIRFLOW_BREEZE_WORKSPACE_NAME="${AIRFLOW_BREEZE_WORKSPACE_NAME:=$(cat ${AIRFLOW_BREEZE_WORKSPACE_FILE} 2>/dev/null)}"
export AIRFLOW_BREEZE_WORKSPACE_NAME="${AIRFLOW_BREEZE_WORKSPACE_NAME:="default"}"

# Cache workspace value for subsequent executions
echo ${AIRFLOW_BREEZE_WORKSPACE_NAME} > ${AIRFLOW_BREEZE_WORKSPACE_FILE}

#################### Directories #######################################################

export AIRFLOW_BREEZE_CONFIG_DIR="${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/airflow-breeze-config"
export AIRFLOW_BREEZE_KEYS_DIR="${AIRFLOW_BREEZE_CONFIG_DIR}/keys"
export AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/incubator-airflow
export AIRFLOW_BREEZE_OUTPUT_DIR=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/output

################## Files ###############################################################
export AIRFLOW_BREEZE_BASH_HISTORY_FILE=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.bash_history
export AIRFLOW_BREEZE_PROJECT_ID_FILE=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.project_id
export AIRFLOW_BREEZE_KEY_FILE=${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.key
export AIRFLOW_BREEZE_KEY_NAME="${AIRFLOW_BREEZE_KEY_NAME:=$(cat ${AIRFLOW_BREEZE_KEY_FILE} 2>/dev/null)}"

#################### Check project id presence ##############################################

if [[ -z "${AIRFLOW_BREEZE_PROJECT_ID:-}" ]]; then
  if [[ -f ${AIRFLOW_BREEZE_PROJECT_ID_FILE} ]]; then
     export AIRFLOW_BREEZE_PROJECT_ID=$(cat ${AIRFLOW_BREEZE_PROJECT_ID_FILE})
  else
    usage
    echo
    echo "ERROR: Missing project id. Specify it with -p <GCP_PROJECT_ID>"
    echo
    exit 1
  fi
fi


#################### Setup image name ##############################################
IMAGE_NAME="gcr.io/${AIRFLOW_BREEZE_PROJECT_ID}/airflow-breeze:${AIRFLOW_REPOSITORY_BRANCH}"

#################### Cleanup image if requested ########################################
if [[ "${CLEANUP_IMAGE}" == "true" ]]; then
    cleanup
fi

#################### Check if project id changed ########################################
if [[ -f ${AIRFLOW_BREEZE_PROJECT_ID_FILE} ]]; then
    OLD_AIRFLOW_BREEZE_PROJECT_ID=$(cat ${AIRFLOW_BREEZE_PROJECT_ID_FILE})
    if [[ ${AIRFLOW_BREEZE_PROJECT_ID} != ${OLD_AIRFLOW_BREEZE_PROJECT_ID} ]]; then
        echo
        echo "The config directory checked out belongs to different project:" \
             " ${OLD_AIRFLOW_BREEZE_PROJECT_ID}. "
        echo "You are switching to project ${AIRFLOW_BREEZE_PROJECT_ID}. "
        echo
        ${MY_DIR}/confirm "This will remove config dir and re-download it."
        rm -rvf  "${AIRFLOW_BREEZE_CONFIG_DIR}"
        rm -v ${AIRFLOW_BREEZE_PROJECT_ID_FILE}
    fi
fi

################## Image name ###############################################################
export AIRFLOW_BREEZE_IMAGE_NAME=${IMAGE_NAME="gcr.io/${AIRFLOW_BREEZE_PROJECT_ID}/airflow-breeze:${AIRFLOW_REPOSITORY_BRANCH}"}

################## Check out incubator airflow dir #############################################
if [[ ! -d "${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}" ]]; then
  echo
  echo "The workspace ${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR} does not exist."
  echo
  if [[ "${AIRFLOW_REPOSITORY}" == "" ]]; then
      echo
      echo "You should -R flag to use your fork of the main apache repository"
      echo
      echo "Fork apache repository: ${APACHE_AIRFLOW_REPO}"
      echo
      exit 1
  fi
  echo "Attempting to clone ${AIRFLOW_REPOSITORY} to ${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}"
  echo "and checking out ${AIRFLOW_REPOSITORY_BRANCH} branch"
  echo
  mkdir -p "${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}" \
  && chmod 777 "${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}" \
  && git clone "${AIRFLOW_REPOSITORY}" "${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}" \
  && pushd "${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}" \
  && git checkout "${AIRFLOW_REPOSITORY_BRANCH}" \
  && popd
  echo
  echo
  echo "Please connect the GitHub fork of your repositories to Cloud Build:"
  echo
  echo "Please make sure you have your own fork of both repositories:"
  echo "Airflow Breeze: ${AIRFLOW_BREEZE_REPO}"
  echo "Incubator Airflow: ${APACHE_AIRFLOW_REPO}"
  echo
  echo "Both 'airflow-breeze' and 'incubator-airflow' should have triggers defined in Cloud Build"
  echo "In case of 'airflow-breeze' you should configure cloudbuild with '/cloudbuild.yaml' file"
  echo "In case of 'incubator-airflow' you should configure cloudbuild with '/airflow/contrib/cloudbbuild/cloudbuild.yaml' file"
  echo
  echo "Configure the triggers here https://console.cloud.google.com/cloud-build/triggers?project=${AIRFLOW_BREEZE_PROJECT_ID} "
  echo
  echo "After you do it, you will have to push the 'airflow-breeze' and after it completes"
  echo "'incubator-airflow' in order to trigger cloud builds."
  echo
  echo "You can check status of your builds via "
  echo "https://console.cloud.google.com/cloud-build/builds?project=${AIRFLOW_BREEZE_PROJECT_ID} ."
  echo
  ${MY_DIR}/confirm "Please confirm that you connected both repos"
  echo
fi

################## Check out config dir #############################################
if [[ ! -d ${AIRFLOW_BREEZE_CONFIG_DIR} ]]; then
  echo
  echo "Automatically checking out airflow-breeze-config directory from your Google Cloud Repository:"
  echo
  gcloud source repos --project=${AIRFLOW_BREEZE_PROJECT_ID} clone airflow-breeze-config \
    "${AIRFLOW_BREEZE_CONFIG_DIR}" || (\
     echo && echo "Bootstrapping airflow-breeze-config as it was not found in Google Cloud Repository" && echo && \
     python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME} )

     CLOUDBUILD_FILES=$(cd "${AIRFLOW_BREEZE_CONFIG_DIR}"; find . -name cloudbuild.yaml)
     if [[ ${CLOUDBUILD_FILES} != "" ]]; then
         echo
         echo "In order to deploy notification cloud functions, please create Cloud Build triggers if not already done."
         echo
         echo "Please configure triggers for cloudbuild.yaml file(s) for 'airflow-breze-config' Cloud Source Repository project"
         echo ${CLOUDBUILD_FILES} | tr -s ' ' '\n'| sed 's/^\.\///'
         echo
         echo "Configure them here: https://console.cloud.google.com/cloud-build/triggers/add?project=${AIRFLOW_BREEZE_PROJECT_ID}"
         echo
         echo
         input ${MY_DIR}/confirm "OK to continue after creating the triggers"
     fi
fi

# Cache project value for subsequent executions
echo ${AIRFLOW_BREEZE_PROJECT_ID} > ${AIRFLOW_BREEZE_PROJECT_ID_FILE}

if [[ ${RECREATE_GCP_PROJECT} == "true" ]]; then
    echo && echo "Reconfiguring project in GCP" && echo &&
    (set -a && source "${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env" && set +a && \
        python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}   \
       --recreate-project )
elif [[ ${RECONFIGURE_GCP_PROJECT} == "true" ]]; then
    echo && echo "Reconfiguring project in GCP with new secrets and services" && echo &&
    (set -a && source "${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env" && set +a && \
        python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}  )
fi
if [[ ${LIST_KEYS} == "true" ]]; then
    echo "<KEY_NAME> can be one of: [$(cd ${AIRFLOW_BREEZE_KEYS_DIR} && ls *.json | tr '\n' ',')]"
    exit
fi

################## Check if key exists #############################################
if [[ ! -f "${AIRFLOW_BREEZE_KEYS_DIR}/${AIRFLOW_BREEZE_KEY_NAME}" ]]; then
    echo
    echo "Missing key file ${AIRFLOW_BREEZE_KEYS_DIR}/${AIRFLOW_BREEZE_KEY_NAME}"
    echo
    echo "Authentication to Google Cloud Platform will not work."
    echo "You need to select the key once with --key-name <KEY_NAME>"
    echo "Where <KEY_NAME> can be one of: [$(cd ${AIRFLOW_BREEZE_KEYS_DIR} && ls *.json | tr '\n' ',')]"
    echo
    ${MY_DIR}/confirm "Proceeding without key"
    echo
fi

# Cache key value for subsequent executions
echo ${AIRFLOW_BREEZE_KEY_NAME} > ${AIRFLOW_BREEZE_KEY_FILE}

################## Check if .bash_history file exists #############################
if [[ ! -f "${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.bash_history" ]]; then
  echo
  echo "Creating empty .bash_history"
  touch ${MY_DIR}/${AIRFLOW_BREEZE_WORKSPACE_NAME}/.bash_history
  echo
fi

################## Download image #############################
if [[ "${DOWNLOAD_IMAGE}" == "true" ]]; then
  download
fi

################## Build image locally #############################
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


################## Decrypt all files variables #############################
pushd ${AIRFLOW_BREEZE_KEYS_DIR}
FILES=$(ls *.json.enc *.pem.enc 2>/dev/null || true)
echo "Decrypting all files '${FILES}'"
for FILE in ${FILES}
do
  gcloud kms decrypt --plaintext-file $(basename ${FILE} .enc) --ciphertext-file ${FILE} \
     --location=global --keyring=incubator-airflow --key=service_accounts_crypto_key \
     --project=${AIRFLOW_BREEZE_PROJECT_ID} \
        && echo Decrypted ${FILE}
done
chmod -v og-rw *
popd
echo
echo "All files decrypted! "
echo
################## Decrypt all variables #############################
echo
echo "Decrypting encrypted variables"
echo
(set -a && source "${AIRFLOW_BREEZE_CONFIG_DIR}/variables.env" && set +a && \
 python ${MY_DIR}/_decrypt_encrypted_variables.py ${AIRFLOW_BREEZE_PROJECT_ID} >\
      ${AIRFLOW_BREEZE_CONFIG_DIR}/decrypted_variables.env)
echo
echo "Variables decrypted! "
echo

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
echo " PYTHON_VERSION             = ${PYTHON_VERSION}"
echo
echo " PROJECT                    = ${AIRFLOW_BREEZE_PROJECT_ID}"
echo
echo " WORKSPACE                  = ${AIRFLOW_BREEZE_WORKSPACE_NAME}"
echo
echo " AIRFLOW_SOURCE_DIR         = ${AIRFLOW_BREEZE_INCUBATOR_AIRFLOW_DIR}"
echo " AIRFLOW_BREEZE_KEYS_DIR    = ${AIRFLOW_BREEZE_KEYS_DIR}"
echo " AIRFLOW_BREEZE_CONFIG_DIR  = ${AIRFLOW_BREEZE_CONFIG_DIR}"
echo " AIRFLOW_BREEZE_OUTPUT_DIR  = ${AIRFLOW_BREEZE_OUTPUT_DIR}"
echo
echo " GCP_SERVICE_KEY            = ${AIRFLOW_BREEZE_KEY_NAME}"
echo
echo " PORT FORWARDING            = ${DOCKER_PORT_ARG}"
echo
echo "*************************************************************************"


run_container
