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

# Repositories

APACHE_AIRFLOW_REPO=https://github.com/apache/airflow.git
APACHE_AIRFLOW_REPO_GIT=git@github.com:apache/airflow.git

AIRFLOW_BREEZE_REPO=https://github.com/PolideaInternal/airflow-breeze

#################### Port forwarding settings
# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""
RUN_DOCKER=true

#################### Build image settings

# If true, the docker image is rebuilt locally. Can be disabled with -r
REBUILD=true
# Whether to upload image to the GCR Repository
UPLOAD_IMAGE=false
# Whether to download image to the GCR Repository
DOWNLOAD_IMAGE=false
# Whether to cleanup local image
CLEANUP_IMAGE=false
# Whether to list keys
LIST_KEYS=false
# initializes local virtualenv
INITIALIZE_LOCAL_VIRTUALENV=false
# sync master
SYNC_MASTER=false
# Repository which is used to clone Airflow from - when
# it's not yet checked out (default is the Apache one)
AIRFLOW_REPOSITORY=""
# Branch of the repository to check out when it's first cloned
AIRFLOW_REPOSITORY_BRANCH="master"

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

#################### Compares the boot
COMPARE_BOOTSTRAP_CONFIG=false

#################### Helper functions

# Helper function for building the docker image locally.
build_local () {
  echo
  echo "Building docker image '${IMAGE_NAME}'"
  docker build  \
    --build-arg AIRFLOW_REPO_URL=https://github.com/PolideaInternal/airflow.git \
    --build-arg AIRFLOW_REPO_BRANCH=wip-cloud-build \
    . -t ${IMAGE_NAME}
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
  set +e
  docker pull ${IMAGE_NAME}
  set -e
  return $?
}

cleanup () {
  echo "Removing local image ${IMAGE_NAME} ..."
  docker rmi ${IMAGE_NAME}
  exit 0
}

# Builds a docker run command based on settings and evaluates it.
#
# The workspace is run in an interactive bash session and the airflow
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
 -v ${AIRFLOW_BREEZE_AIRFLOW_DIR}:/workspace \
 -v ${AIRFLOW_BREEZE_OUTPUT_DIR}:/airflow/output \
 -v ${GCP_CONFIG_DIR}:/root/config \
 --env-file=${GCP_CONFIG_DIR}/decrypted_variables.env \
 -e PYTHON_VERSION=${AIRFLOW_BREEZE_PYTHON_VERSION} \
 -e AIRFLOW_BREEZE_TEST_SUITE=${AIRFLOW_BREEZE_TEST_SUITE} \
 -e AIRFLOW_BREEZE_SHORT_SHA=${AIRFLOW_BREEZE_SHORT_SHA} \
 -e GCP_CONFIG_DIR=/root/config \
 -e GCP_SERVICE_ACCOUNT_KEY_NAME=${AIRFLOW_BREEZE_KEY_NAME} \
 -v ${AIRFLOW_BREEZE_BASH_HISTORY_FILE}:/root/.bash_history \
  ${DOCKER_PORT_ARG} $@ ${IMAGE_NAME} /bin/bash -c \"/airflow/_init.sh ${POST_INIT_ARG}\"
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

check_encrypt_decrypt_permission() {
    ################## Checking permissions for KMS #############################
  echo "*************************************************************************"
  echo
  echo "Checking required permissions in KMS"
  echo
  echo "*************************************************************************"
    echo "TEST" | gcloud kms encrypt --plaintext-file=- --ciphertext-file=- \
         --location=global --keyring=airflow --key=airflow_crypto_key \
         --project=${AIRFLOW_BREEZE_PROJECT_ID} >/dev/null || \
         (echo "ERROR! You should have KMS Encrypt/Decrypt Role assigned in Google Cloud Platform. Exiting!" && exit 1)
}

decrypt_all_files() {
    ################## Decrypt all files variables #############################
    pushd ${AIRFLOW_BREEZE_KEYS_DIR}
    FILES=$(ls *.json.enc *.pem.enc 2>/dev/null || true)
    echo "Decrypting all new encrypted files"
    for FILE in ${FILES}
    do
      DECRYPTED_FILE=$(basename ${FILE} .enc)
      if [[ ${FILE} -nt ${DECRYPTED_FILE} ]]; then
          gcloud kms decrypt --plaintext-file $(basename ${FILE} .enc) --ciphertext-file ${FILE} \
             --location=global --keyring=airflow --key=airflow_crypto_key \
             --project=${AIRFLOW_BREEZE_PROJECT_ID} \
                && echo Decrypted ${FILE}
      else
        echo "Skipping the unchanged and already decrypted ${FILE}"
      fi
    done
    chmod -v og-rw *
    popd
    echo
    echo "All files decrypted! "
    echo
}

decrypt_all_variables() {
    ################## Decrypt all variables #############################
    echo
    echo "Decrypting encrypted variables"
    echo
    (set -a && source "${GCP_CONFIG_DIR}/variables.env" && set +a && \
     bash ${MY_DIR}/_decrypt_encrypted_variables.sh ${AIRFLOW_BREEZE_PROJECT_ID} >\
          ${GCP_CONFIG_DIR}/decrypted_variables.env)
    echo
    echo "Variables decrypted! "
    echo
}

usage() {
      echo """

Usage ${CMDNAME} [FLAGS] [-t <TEST_TARGET> | -x <COMMAND> ]

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
        '<WORKSPACE>/config/key' folder. Cached between runs. If not
        specified, you need to confirm that you want to enter the environment without
        the key. You can also switch keys manually after entering the environment
        via 'gcloud auth activate-service-account /root/config/keys/<KEY>'.

-K, --key-list
        List all service keys that can be used with --key-name flag.

-P, --python <PYTHON_VERSION>
        Python virtualenv used by default. One of ('3.5', '3.6'). [3.5]

-f, --forward-webserver-port <PORT_NUMBER>
        Optional - forward the port PORT_NUMBER to airflow's webserver (you must start
        the server with 'airflow webserver' command manually).

-F, --forward-postgres-port <PORT_NUMBER>
        Optional - forward the port PORT_NUMBER to airflow's Postgres database. You can
        login to the database as the user "root" with password "airflow". Database of airflow
        is named "airflow/airflow.db".

Reconfiguring existing project:

-g, --reconfigure-gcp-project
        Reconfigures the project already present in the workspace.
        It adds all new variables in case they were added, creates new service accounts
        and updates to latest version of the used notification cloud functions.

-G, --recreate-gcp-project
        Recreates the project already present in the workspace. DELETES AND RECREATES
        all sensitive resources. DELETES AND RECREATES buckets with result of builds
        DELETES AND RECREATES service account keys, DELETES AND GENERATES encrypted
        passwords. Then it performs all actions as in reconfigure project.

-z, --compare-bootstrap-config
        Compares bootstrap configuration with current workspace configuration. It will
        report differences found and suggestions how those two should be aligned.

Initializing your local virtualenv:

-e, --initialize-local-virtualenv
        Initializes locally created virtualenv installing all dependencies of Airflow.
        This local virtualenv can be used to aid autocompletion and IDE support as
        well as run unit tests directly from the IDE. You need to have virtualenv
        activated before running this command.

Managing the docker image of airflow-breeze:

-i, --do-not-rebuild-image
        Don't rebuild the airflow docker image locally

-u, --upload-image
        After rebuilding, also upload the image to GCR repository
        (gcr.io/<GCP_PROJECT_ID>/airflow-breeze). Needs GCP_PROJECT_ID.

-d, --download-image
        Downloads the image from GCR repository (gcr.io/<GCP_PROJECT_ID>/airflow-breeze)
        rather than build it locally. Needs GCP_PROJECT_ID.

-c, --cleanup-image
        Clean your local copy of the airflow docker image.
        Needs GCP_PROJECT_ID.


Automated checkout of airflow project:

-R, --repository [REPOSITORY]
        Repository to clone in case the workspace is not checked out yet
        [${AIRFLOW_REPOSITORY}].
-B, --branch [BRANCH]
        Branch to check out when cloning the repository specified by -R. [master]

-S, --synchronise-master
        Synchronizes master of your local and origin remote with the main apache repository.

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

cat << "EOF"


                                              @&&&&&&@
                                             @&&&&&&&&&&&@
                                            &&&&&&&&&&&&&&&&
                                                    &&&&&&&&&&
                                                        &&&&&&&
                                                         &&&&&&&
                                       @@@@@@@@@@@@@@@@   &&&&&&
                                      @&&&&&&&&&&&&&&&&&&&&&&&&&&
                                     &&&&&&&&&&&&&&&&&&&&&&&&&&&&
                                                     &&&&&&&&&&&&
                                                         &&&&&&&&&
                                                       &&&&&&&&&&&&
                                                  @@&&&&&&&&&&&&&&&@
                               @&&&&&&&&&&&&&&&&&&&&&&&&&&&&  &&&&&&
                              &&&&&&&&&&&&&&&&&&&&&&&&&&&&    &&&&&&
                             &&&&&&&&&&&&&&&&&&&&&&&&         &&&&&&
                                                             &&&&&&
                                                           &&&&&&&
                                                        @&&&&&&&&
                        @&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
                       &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
                      &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&



                 @&&&@       &&  @&&&&&&&&&&&   &&&&&&&&&&&&  &&            &&&&&&&&&&  &&&     &&&     &&&
                &&& &&&      &&  @&&       &&&  &&            &&          &&&       &&&@ &&&   &&&&&   &&&
               &&&   &&&     &&  @&&&&&&&&&&&&  &&&&&&&&&&&   &&          &&         &&&  &&& &&& &&@ &&&
              &&&&&&&&&&&    &&  @&&&&&&&&&     &&            &&          &&@        &&&   &&@&&   &&@&&
             &&&       &&&   &&  @&&     &&&@   &&            &&&&&&&&&&&  &&&&&&&&&&&&     &&&&   &&&&

            &&&&&&&&&&&&   &&&&&&&&&&&&   &&&&&&&&&&&@  &&&&&&&&&&&&   &&&&&&&&&&&   &&&&&&&&&&&
            &&&       &&&  &&        &&&  &&            &&&                  &&&&    &&
            &&&&&&&&&&&&@  &&&&&&&&&&&&   &&&&&&&&&&&   &&&&&&&&&&&       &&&&       &&&&&&&&&&
            &&&        &&  &&   &&&&      &&            &&&             &&&&         &&
            &&&&&&&&&&&&&  &&     &&&&@   &&&&&&&&&&&@  &&&&&&&&&&&&  @&&&&&&&&&&&   &&&&&&&&&&&


EOF

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
        echo
        echo "Login and logout afterwards"
        echo
    else
        echo "You do not have enhanced version of getopt binary in the path."
        echo "Please install latest/GNU version."
    fi
    echo
    exit 1
fi

PARAMS=$(getopt \
    -o hp:w:k:KP:f:F:iudcgGzeR:B:St:x: \
    -l help,project:,workspace:,key-name:,key-list,python:,forward-webserver-port:,forward-postgres-port:,\
do-not-rebuild-image,upload-image,dowload-image,cleanup-image,reconfigure-gcp-project,\
recreate-gcp-project,compare-bootstrap-config,initialize-local-virtualenv,repository:,\
branch:,synchronise-master,test-target:,execute: \
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
      AIRFLOW_BREEZE_PYTHON_VERSION="${2}"; shift 2 ;;
    -f|--forward-webserver-port)
      DOCKER_PORT_ARG="-p 127.0.0.1:${2}:8080 ${DOCKER_PORT_ARG}"; shift 2 ;;
    -F|--forward-postgres-port)
      DOCKER_PORT_ARG="-p 127.0.0.1:${2}:5432 ${DOCKER_PORT_ARG}"; shift 2 ;;
    -i|--do-not-rebuild-image)
      REBUILD=false; shift ;;
    -u|--upload-image)
      UPLOAD_IMAGE=true
      if [[ ! ${DOWNLOAD_IMAGE} != "false" || ${CLEANUP_IMAGE} != "false" ]]; then
         echo "Cannot specify two of 'upload', 'download' or 'cleanup' at the same time"
         exit 1
      fi
      shift ;;
    -d|--download-image)
      DOWNLOAD_IMAGE=true
      REBUILD=false
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
      REBUILD=false
      RUN_DOCKER=false
      shift ;;
    -g|--reconfigure-gcp-project)
      RECONFIGURE_GCP_PROJECT=true; RUN_DOCKER=false; shift ;;
    -G|--recreate-gcp-project)
      RECREATE_GCP_PROJECT=true; RUN_DOCKER=false; shift ;;
    -z|--compare-bootstrap-config)
      COMPARE_BOOTSTRAP_CONFIG=true; RUN_DOCKER=false; shift ;;
    -e|--initialize-local-virtualenv)
      INITIALIZE_LOCAL_VIRTUALENV=true; RUN_DOCKER=false; shift ;;
    -R|--repository)
      AIRFLOW_REPOSITORY="${2}"; shift 2 ;;
    -B|--branch)
      AIRFLOW_REPOSITORY_BRANCH="${2}"; shift 2 ;;
    -S|--synchronize-master)
      SYNC_MASTER="true"; RUN_DOCKER=false; shift ;;
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
export AIRFLOW_BREEZE_WORKSPACE_DIR="${MY_DIR}/workspaces/${AIRFLOW_BREEZE_WORKSPACE_NAME}"

if [[ ${AIRFLOW_BREEZE_WORKSPACE_NAME} == */* ]]; then
    echo
    echo "Your workspace (${AIRFLOW_BREEZE_WORKSPACE_NAME}) should not contain /"
    echo "It should be a simple directory name."
    echo
    exit 1
fi

# Cache workspace value for subsequent executions
echo ${AIRFLOW_BREEZE_WORKSPACE_NAME} > ${AIRFLOW_BREEZE_WORKSPACE_FILE}

#################### Directories #######################################################

export GCP_CONFIG_DIR="${AIRFLOW_BREEZE_WORKSPACE_DIR}/config"
export AIRFLOW_BREEZE_KEYS_DIR="${GCP_CONFIG_DIR}/keys"
export AIRFLOW_BREEZE_AIRFLOW_DIR=${AIRFLOW_BREEZE_WORKSPACE_DIR}/airflow
export AIRFLOW_BREEZE_OUTPUT_DIR=${AIRFLOW_BREEZE_WORKSPACE_DIR}/output

################## Files ###############################################################
export AIRFLOW_BREEZE_BASH_HISTORY_FILE=${AIRFLOW_BREEZE_WORKSPACE_DIR}/.bash_history
export AIRFLOW_BREEZE_PROJECT_ID_FILE=${AIRFLOW_BREEZE_WORKSPACE_DIR}/.project_id
export AIRFLOW_BREEZE_KEY_FILE=${AIRFLOW_BREEZE_WORKSPACE_DIR}/.key
export AIRFLOW_BREEZE_KEY_NAME="${AIRFLOW_BREEZE_KEY_NAME:=$(cat ${AIRFLOW_BREEZE_KEY_FILE} 2>/dev/null)}"
export AIRFLOW_BREEZE_PYTHON_VERSION_FILE=${AIRFLOW_BREEZE_WORKSPACE_DIR}/.python_version
export AIRFLOW_BREEZE_PYTHON_VERSION="${AIRFLOW_BREEZE_PYTHON_VERSION:=$(cat ${AIRFLOW_BREEZE_PYTHON_VERSION_FILE} 2>/dev/null)}"
export AIRFLOW_BREEZE_PYTHON_VERSION="${AIRFLOW_BREEZE_PYTHON_VERSION:=3.6}"


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

#################### Check project python version ##########################################

ALLOWED_PYTHON_VERSIONS=" 3.5 3.6 "

if [[ ${ALLOWED_PYTHON_VERSIONS} != *" ${AIRFLOW_BREEZE_PYTHON_VERSION} "* ]]; then
    echo
    echo "ERROR! Allowed Python versions are${ALLOWED_PYTHON_VERSIONS}and you have '${AIRFLOW_BREEZE_PYTHON_VERSION}'"
    echo
    exit 1
fi

#################### Migrate config directory #############################################

if [[ -d "${AIRFLOW_BREEZE_WORKSPACE_DIR}/airflow-breeze-config" ]]; then
    echo
    echo "WARNING! Old structure of directory detected."
    echo "Name of  directory 'airflow-breeze-config' has been changed to 'airflow-config'"
    echo
    echo "Start automatic migration"
    mv "${AIRFLOW_BREEZE_WORKSPACE_DIR}/airflow-breeze-config" "${GCP_CONFIG_DIR}"
    echo "Automatic migration was successful."
    echo
fi

#################### Test suite generation ##########################################
# First 6 characters of the ASCII-only user name + python version withstripped .

USER=${USER:=""}
ASCII_USER=$(echo ${USER} | env LANG=C sed 's/[^a-zA-Z0-9]//g')
NUMERIC_PYTHON_VERSION=$(echo ${AIRFLOW_BREEZE_PYTHON_VERSION} | sed 's/\.//')
AIRFLOW_BREEZE_TEST_SUITE=${ASCII_USER:0:6}${NUMERIC_PYTHON_VERSION}

#################### Short SHA ##########################################
# 7 random alphanum characters stored in .random file which you can delete to regenerate

RANDOM_FILE=${MY_DIR}/.random

if [[ ! -f ${RANDOM_FILE} ]]; then
    date | md5sum | head -c 7 > ${RANDOM_FILE}
fi
AIRFLOW_BREEZE_SHORT_SHA=$(cat ${RANDOM_FILE})

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
        rm -rvf  "${GCP_CONFIG_DIR}"
        rm -v ${AIRFLOW_BREEZE_PROJECT_ID_FILE}
    fi
fi

################## Image name ###############################################################
export AIRFLOW_BREEZE_IMAGE_NAME=${IMAGE_NAME="gcr.io/${AIRFLOW_BREEZE_PROJECT_ID}/airflow-breeze:${AIRFLOW_REPOSITORY_BRANCH}"}

################## Check out airflow dir #############################################
if [[ ! -d "${AIRFLOW_BREEZE_AIRFLOW_DIR}" ]]; then
  echo
  echo "The workspace ${AIRFLOW_BREEZE_AIRFLOW_DIR} does not exist."
  echo
  if [[ "${AIRFLOW_REPOSITORY}" == "" ]]; then
      echo
      echo "You should -R flag to use your fork of the main apache repository"
      echo
      echo "Fork apache repository: ${APACHE_AIRFLOW_REPO}"
      echo
      exit 1
  fi
  echo "Attempting to clone ${AIRFLOW_REPOSITORY} to ${AIRFLOW_BREEZE_AIRFLOW_DIR}"
  echo "and checking out ${AIRFLOW_REPOSITORY_BRANCH} branch"
  echo
  mkdir -p "${AIRFLOW_BREEZE_AIRFLOW_DIR}" \
  && chmod 777 "${AIRFLOW_BREEZE_AIRFLOW_DIR}" \
  && git clone "${AIRFLOW_REPOSITORY}" "${AIRFLOW_BREEZE_AIRFLOW_DIR}" \
  && pushd "${AIRFLOW_BREEZE_AIRFLOW_DIR}" \
  && git checkout "${AIRFLOW_REPOSITORY_BRANCH}" \
  && popd
  echo
  echo
  echo "Please connect the GitHub fork of your repositories to Cloud Build:"
  echo
  echo "Please make sure you have your own fork of both repositories:"
  echo "Airflow Breeze: ${AIRFLOW_BREEZE_REPO}"
  echo "Airflow: ${APACHE_AIRFLOW_REPO}"
  echo
  echo
  echo "Enable Google Cloud Build Application in both projects:"
  echo
  echo " * fork of Apache's https://github.com/apache/airflow"
  echo " * fork of Airflow Breeze http://github.com/PolideaInternal/airflow-breeze"
  echo
  echo "This can be done via: https://github.com/marketplace/google-cloud-build"
  echo
  echo "After you set it up it, you have to push the 'airflow-breeze' and wait until it completes."
  echo "Then any time you push 'airflow' it will perform automated build and testing of your project."
  echo
  echo "In the future you can always check status of your builds via "
  echo "https://console.cloud.google.com/cloud-build/builds?project=${AIRFLOW_BREEZE_PROJECT_ID} ."
  echo
  ${MY_DIR}/confirm "Please confirm that you connected both repos"
  echo
fi

################## Check out config dir #############################################
if [[ ! -d ${GCP_CONFIG_DIR} ]]; then
  echo
  echo "Automatically checking out airflow-breeze-config repo from your Google Cloud "
  echo "Repository in ${GCP_CONFIG_DIR} folder."
  echo
  mkdir -pv "${GCP_CONFIG_DIR}"
  gcloud source repos --project=${AIRFLOW_BREEZE_PROJECT_ID} clone airflow-breeze-config \
    "${GCP_CONFIG_DIR}" || (\
     echo && echo "Bootstrapping airflow-breeze-config as it was not found in Google Cloud Repository" && echo && \
     python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${AIRFLOW_BREEZE_WORKSPACE_DIR} )

     CLOUDBUILD_FILES=$(cd "${GCP_CONFIG_DIR}"; find . -name cloudbuild.yaml)
     if [[ ${CLOUDBUILD_FILES} != "" ]]; then
         echo
         echo "In order to enable notifications, please setup trigger(s) for Cloud Build"
         echo
         echo "Choose one of the cloudbuild.yaml file(s) for 'airflow-breeze-config' project"
         echo ${CLOUDBUILD_FILES} | tr -s ' ' '\n'| sed 's/^\.\///'
         echo
         echo "Configure them here: https://console.cloud.google.com/cloud-build/triggers/add?project=${AIRFLOW_BREEZE_PROJECT_ID}"
         echo
         echo
         ${MY_DIR}/confirm "Please confirm that you created the trigger(s)"
     fi
fi

# Cache project and python version for subsequent executions
echo ${AIRFLOW_BREEZE_PROJECT_ID} > ${AIRFLOW_BREEZE_PROJECT_ID_FILE}
echo ${AIRFLOW_BREEZE_PYTHON_VERSION} > ${AIRFLOW_BREEZE_PYTHON_VERSION_FILE}

check_encrypt_decrypt_permission

if [[ ${RECREATE_GCP_PROJECT} == "true" ]]; then
    echo && echo "Reconfiguring project in GCP" && echo &&
    (set -a && source "${GCP_CONFIG_DIR}/variables.env" && set +a && \
        python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${AIRFLOW_BREEZE_WORKSPACE_DIR}   \
       --recreate-project )
    decrypt_all_files
    decrypt_all_variables
elif [[ ${RECONFIGURE_GCP_PROJECT} == "true" ]]; then
    echo && echo "Reconfiguring project in GCP with new secrets and services" && echo &&
    (set -a && source "${GCP_CONFIG_DIR}/variables.env" && set +a && \
        python3 ${MY_DIR}/bootstrap/_bootstrap_airflow_breeze_config.py \
       --gcp-project-id ${AIRFLOW_BREEZE_PROJECT_ID} \
       --workspace ${AIRFLOW_BREEZE_WORKSPACE_DIR}  )
    decrypt_all_files
    decrypt_all_variables
elif [[ ${COMPARE_BOOTSTRAP_CONFIG} == "true" ]]; then
 (set -a && source "${GCP_CONFIG_DIR}/variables.env" &&
     source "${GCP_CONFIG_DIR}/decrypted_variables.env" &&
     set +a &&
     ${MY_DIR}/compare_workspace_with_bootstrap.py)
fi
if [[ ${INITIALIZE_LOCAL_VIRTUALENV} == "true" ]]; then
   # Check if we are in virtualenv
   set +e
   echo -e "import sys\nif not hasattr(sys,'real_prefix'):\n  sys.exit(1)" | python
   RES=$?
   set -e
   if [[ ${RES} != "0" ]]; then
        echo
        echo "Initializing local virtualenv only works when you have virtualenv activated"
        echo
        echo "Please enter your local virtualenv before (for example using 'workon' from virtualenvwrapper) "
        echo
        exit 1
   else
        AIRFLOW_HOME_DIR=${AIRFLOW_HOME:=${HOME}/airflow}
        echo
        echo "Initializing the virtualenv: $(which python)!"
        echo
        echo "This will wipe out ${AIRFLOW_HOME_DIR} and reset all the databases!"
        echo
        ${MY_DIR}/confirm "Proceeding with the initialization"
        echo
        pushd ${AIRFLOW_BREEZE_AIRFLOW_DIR}
        SYSTEM=$(uname -s)
        echo "#######################################################################"
        echo "  If you have trouble installing all dependencies you might need to run:"
        echo
        if [[ ${SYSTEM} == "Darwin" ]]; then
            echo "  brew install sqlite mysql postgresql"
        else
            echo "sudo apt-get install openssl sqlite libmysqlclient-dev libmysqld-dev libpq-dev libpq-dev python-psycopg2 postgresql --confirm"
        fi
        echo
        echo "#######################################################################"
        pip install -e .[devel-all]
        popd
        echo
        echo "Wiping and recreating ${AIRFLOW_HOME_DIR}"
        echo
        rm -rvf ${AIRFLOW_HOME_DIR}
        mkdir -p ${AIRFLOW_HOME_DIR}
        echo
        echo "Resetting AIRFLOW sqlite database"
        echo
        unset AIRFLOW__CORE__UNIT_TEST_MODE
        airflow db reset -y
        echo
        echo "Resetting AIRFLOW sqlite unit test database"
        echo
        export AIRFLOW__CORE__UNIT_TEST_MODE=True
        airflow db reset -y
        exit
   fi
fi

if [[ ${LIST_KEYS} == "true" ]]; then
    echo "<KEY_NAME> can be one of: [$(cd ${AIRFLOW_BREEZE_KEYS_DIR} && ls *.json | tr '\n' ',')]"
    exit
fi

if [[ ${SYNC_MASTER} == "true" ]]; then
        pushd ${AIRFLOW_BREEZE_AIRFLOW_DIR} || exit 1
        set +e
        git ls-remote --exit-code apache 2>/dev/null >/dev/null
        if [[ $? != 0 ]]; then
            echo "Adding remote apache ${APACHE_AIRFLOW_REPO_GIT}"
            git remote add apache "${APACHE_AIRFLOW_REPO_GIT}"
        fi
        echo "Fetching apache repository"
        git fetch apache
        echo "Force local master to be the same as remote apache master"
        git branch -f master apache/master
        echo "Pushing local master to remote origin master"
        git push origin master:master
        set -e
        popd || exit 1
   exit
fi

if [[ ${RUN_DOCKER} == "true" ]]; then
    ################## Check if .bash_history file exists #############################
    if [[ ! -f "${AIRFLOW_BREEZE_WORKSPACE_DIR}/.bash_history" ]]; then
      echo
      echo "Creating empty .bash_history"
      touch ${AIRFLOW_BREEZE_WORKSPACE_DIR}/.bash_history
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
      if [[ $? != "0" ]]; then
          echo
          echo "The local image does not exist. Building it. It might take up to 30 minutes."
          echo
          echo "Press enter to continue"
          read
          build_local
      fi
    fi

    decrypt_all_files
    decrypt_all_variables
    ################## Check if key exists #############################################
    if [[ ! -f "${AIRFLOW_BREEZE_KEYS_DIR}/${AIRFLOW_BREEZE_KEY_NAME}" ]]; then
        echo
        if [[ ${AIRFLOW_BREEZE_KEY_NAME} == "" ]]; then
            echo "Service account key not specified"
        else
            echo "Missing key file ${AIRFLOW_BREEZE_KEYS_DIR}/${AIRFLOW_BREEZE_KEY_NAME}"
        fi
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

    echo
    echo "Decrypted variables (only visible when you run local environment!):"
    echo
    cat ${GCP_CONFIG_DIR}/decrypted_variables.env
    echo

    echo "*************************************************************************"
    echo
    echo " Entering airflow development environment in docker"
    echo
    echo " AIRFLOW_BREEZE_PYTHON_VERSION = ${AIRFLOW_BREEZE_PYTHON_VERSION}"
    echo
    echo " PROJECT                       = ${AIRFLOW_BREEZE_PROJECT_ID}"
    echo
    echo " WORKSPACE                     = ${AIRFLOW_BREEZE_WORKSPACE_NAME}"
    echo
    echo " AIRFLOW_SOURCE_DIR            = ${AIRFLOW_BREEZE_AIRFLOW_DIR}"
    echo " AIRFLOW_BREEZE_KEYS_DIR       = ${AIRFLOW_BREEZE_KEYS_DIR}"
    echo " GCP_CONFIG_DIR                = ${GCP_CONFIG_DIR}"
    echo " AIRFLOW_BREEZE_OUTPUT_DIR     = ${AIRFLOW_BREEZE_OUTPUT_DIR}"
    echo " AIRFLOW_BREEZE_TEST_SUITE     = ${AIRFLOW_BREEZE_TEST_SUITE}"
    echo " AIRFLOW_BREEZE_SHORT_SHA      = ${AIRFLOW_BREEZE_SHORT_SHA}"
    echo
    echo " AIRFLOW_BREEZE_KEY_NAME       = ${AIRFLOW_BREEZE_KEY_NAME}"
    echo
    echo " PORT FORWARDING               = ${DOCKER_PORT_ARG}"
    echo
    echo "*************************************************************************"


    echo "*************************************************************************"
    echo
    echo " Comparing your current configuration with bootstrap configuration"
    echo
    set +e
    (set -a && source "${GCP_CONFIG_DIR}/variables.env" &&
     source "${GCP_CONFIG_DIR}/decrypted_variables.env" &&
     set +a &&
     ${MY_DIR}/compare_workspace_with_bootstrap.py)
    RES=$?
    set -e
    if [[ ${RES} != 0 ]]; then
         ${MY_DIR}/confirm "Proceeding without alignment"
    fi
    echo

    run_container $@
fi
