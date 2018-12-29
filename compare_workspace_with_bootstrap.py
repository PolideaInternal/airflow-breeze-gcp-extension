#!/usr/bin/env python3
import difflib
import errno
import os
import sys

import subprocess

ENCRYPTED_SUFFIX = '_ENCRYPTED'
TEMPLATE_PREFIX = 'TEMPLATE-'
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

MY_DIR = os.path.dirname(__file__)

confirm = False

VARIABLES = {}


def set_confirm():
    global confirm
    confirm = True


def get_current_workspace_info():
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
    workspace_dir = os.path.join(current_file_dir, "workspaces", workspace)
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
    variable_env_file = os.path.join(incubator_airflow_config_dir, 'variables.env')
    return project_id, workspace_dir, incubator_airflow_config_dir, \
        incubator_airflow_keys_dir, variable_env_file


def read_all_variable_keys(file):
    with open(file, "r") as f:
        text = f.readlines()
    keys = set()
    for line in text:
        if line.strip().startswith("#"):
            continue
        if "=" in line:
            key, val = line.split("=", maxsplit=1)
            keys.add(key)
    return keys


def compare_variable_keys(variable_file, bootstrap_variable_file):
    current_keys = read_all_variable_keys(variable_file)
    bootstrap_keys = read_all_variable_keys(bootstrap_variable_file)
    new_current_keys = current_keys - bootstrap_keys
    new_bootstrap_keys = bootstrap_keys - current_keys
    if len(new_bootstrap_keys) > 0:
        set_confirm()
        print("!" * 80)
        print()
        print("There are new keys added in bootstrap file {}".format(
            bootstrap_variable_file))
        print()
        for key in new_bootstrap_keys:
            print(key)
        print()
        print("Run `./run_environment.sh with --gcp-reconfigure-project` flag to "
              "add the new values to your configuration")
        print()
        print("!" * 80)
    if len(new_current_keys) > 0:
        set_confirm()
        print("!" * 80)
        print()
        print("There are new keys added in your airflow-breeze-config file {}".format(
            variable_file))
        print()
        for key in new_current_keys:
            print(key)
        print()
        print("Please remember to add the new keys to the bootstrap template: {}".format(
            bootstrap_variable_file))
        print()
        print("!" * 80)


def process_templates(content):
    new_content = []
    for line in content:
        for key, value in VARIABLES.items():
            string_to_replace1 = '{{ ' + key + ' }}'
            line = line.replace(string_to_replace1, value)
            string_to_replace2 = '{{' + key + '}}'
            line = line.replace(string_to_replace2, value)
        new_content.append(line)
    return new_content


def check_all_files(config_directory, bootstrap_config_directory):
    real_config_path = os.path.realpath(config_directory)
    for root, dirs, fnames in os.walk(top=real_config_path, topdown=True):
        dirs[:] = [d for d in dirs if d not in ['node_modules', '.git', 'keys']]
        for f in fnames:
            file_path = os.path.join(root, f)
            if "decrypted_variables" in f or f.endswith('.enc') or \
                    f == 'all.variables.yaml' \
                    or f.endswith(".iml") or os.path.islink(file_path):
                continue
            bootstrap_path = os.path.join(
                bootstrap_config_directory + root[len(real_config_path):],
                TEMPLATE_PREFIX + f)
            print("Comparing {} <> {}".format(file_path, bootstrap_path))
            with open(bootstrap_path, "rt") as bootstrap_file:
                text_bootstrap = bootstrap_file.readlines()
            with open(file_path, "rt") as config_file:
                text_config = config_file.readlines()
            # Check if the content is the same after we process it using variables
            processed_bootstrap = process_templates(text_bootstrap)
            if text_config != processed_bootstrap:
                set_confirm()
                print("!" * 80)
                print()
                print("The file in your workspace {} is different than in "
                      "bootstrap {} after processing with current variables".
                      format(file_path, bootstrap_path))
                print()
                for line in difflib.unified_diff(text_config,
                                                 processed_bootstrap):
                    sys.stdout.write(line)  # EOL is there already
                    sys.stdout.flush()
                print()
                print("Please make sure to align them!")
                print()
                print("!" * 80)


if __name__ == '__main__':
    VARIABLES.update(os.environ)
    _project_id, _workspace_dir, _config_dir, _keys_dir, _variable_file = \
        get_current_workspace_info()
    _bootstrap_config_dir = os.path.join(MY_DIR, "bootstrap", "config")
    _bootstrap_variable_file = os.path.join(_bootstrap_config_dir,
                                            TEMPLATE_PREFIX + "variables.env")

    compare_variable_keys(_variable_file, _bootstrap_variable_file)
    check_all_files(_config_dir, _bootstrap_config_dir)

    if confirm:
        sys.exit(1)
