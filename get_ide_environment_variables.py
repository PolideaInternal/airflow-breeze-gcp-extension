import errno
import os
import subprocess

ENCRYPTED_SUFFIX = '_ENCRYPTED'
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

# Run this in airflow-breeze to get list of environment variables to set for
# running the tests via IDE (for example IntelliJ. You should copy&paste
# output of this script to your tests in order to not skip the test
if __name__ == '__main__':
    lowercase_user = os.environ.get('USER').lower()[:8].encode('ascii', errors='ignore')
    current_file_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_file = os.path.join(current_file_dir, ".workspace")
    try:
        with open(workspace_file) as f:
            workspace = f.readline().strip()
    except OSError as e:
        if e.errno == errno.ENOENT:
            raise Exception("Please select workspace by running run_environment.sh first!"
                            " The file {} is missing.".format(workspace_file))
        raise e
    workspace_dir = os.path.join(current_file_dir, workspace)
    incubator_airflow_config_dir = os.path.join(workspace_dir, 'airflow-breeze-config')
    incubator_airflow_keys_dir = os.path.join(incubator_airflow_config_dir, 'keys')
    project_file = os.path.join(workspace_dir, '.project_id')
    try:
        with open(project_file) as f:
            project_id = f.readline().strip()
    except OSError as e:
        if e.errno == errno.ENOENT:
            raise Exception("Please select project with running run_environment.sh first!"
                            " The file {} is missing.".format(project_file))
        raise e
    if not os.path.isdir(incubator_airflow_config_dir):
        print("The {} is not variable dir.".format(incubator_airflow_config_dir))
        exit(1)
    if not os.path.isdir(incubator_airflow_keys_dir):
        print("The {} is not keys dir.".format(incubator_airflow_keys_dir))
        exit(1)
    os.environ['AIRFLOW_BREEZE_CONFIG_DIR'] = incubator_airflow_config_dir
    os.environ['AIRFLOW_BREEZE_TEST_SUITE'] = lowercase_user
    variable_env_file = os.path.join(incubator_airflow_config_dir, 'variables.env')
    with open(variable_env_file) as f:
        lines = f.readlines()
    variable_names = []
    for line in lines:
        if not line.startswith('#') and not line.strip() == "":
            key = line.split('=')[0]
            variable_names.append(key)
            if key.endswith(ENCRYPTED_SUFFIX):
                variable_names.append(key[:-len(ENCRYPTED_SUFFIX)])

    if not os.path.isfile(variable_env_file):
        print("The {} is not variable env file.".format(variable_env_file))
        exit(1)
    variables = subprocess.check_output(
        [
            "/bin/bash", "-c", "set -a && "
                               "source {} && "
                               "set +a && "
                               "printenv".
            format(variable_env_file)
        ]
    ).decode('utf-8')
    all_variables = {}
    for line in variables.splitlines():
        key, val = line.split('=', 1)
        if key.endswith(ENCRYPTED_SUFFIX):
            original_key = key[:-len(ENCRYPTED_SUFFIX)]
            decrypted_val = subprocess.check_output(
                ['bash', '-c',
                 'echo -n "{}" | base64 --decode | '
                 'gcloud kms decrypt --plaintext-file=- '
                 '--ciphertext-file=- --location=global '
                 '--keyring=incubator-airflow '
                 '--project={} '
                 '--key=service_accounts_crypto_key'.format(val, project_id)]). \
                decode('utf-8')
            all_variables[original_key] = decrypted_val
        else:
            all_variables[key] = val
    # Force Unit test mode for the tests
    print("AIRFLOW__CORE__UNIT_TEST_MODE=True")
    # Force enabling of Cloud SQL query tests
    print("GCP_ENABLE_CLOUDSQL_QUERY_TEST=True")

# only print relevant variables (those present in variables.env file)
    for key in variable_names:
        try:
            print("{}={}".format(key, all_variables[key]))
        except KeyError:
            pass
