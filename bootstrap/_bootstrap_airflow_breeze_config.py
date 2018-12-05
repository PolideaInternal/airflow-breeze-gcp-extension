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
#
"""Bootstraps an empty airflow-breeze-config project"""
import json
import subprocess
import sys

import argparse
import os
import shutil
from os.path import dirname, basename


MY_DIR = dirname(__file__)

BOOTSTRAP_CONFIG_DIR = os.path.join(MY_DIR, "config")
CONFIG_REPO_NAME = "airflow-breeze-config"


TARGET_DIR = None


def check_if_config_exists(workspace_dir):
    config_dir = os.path.join(workspace_dir, CONFIG_REPO_NAME)
    if os.path.isdir(config_dir):
        raise Exception("Configuration folder {} already exists. Remove it to "
                        "bootstrap it from scratch".format(config_dir))
    return config_dir


IGNORE_SLACK = False


def ignore_dirs(src, names):
    ignored = []
    if IGNORE_SLACK and basename(src) == 'config' and 'notifications' in names:
        ignored.append('notifications')
    return ignored


def copy_files(source_path, destination_path):
    shutil.copy2(source_path, destination_path)

    # We do not use Jinja2 or another templating system because we want to make
    # bootstrapping works without external dependencies. Also built-in templating
    # is not good enough because it uses $variable syntax that would clash with
    # Bash substitution we use in a number of places. In order to avoid escaping
    # The '$' we use Jinja2 form of template variables '{{ VARIABLE }}'
    # Note strict spaces (!) instead and replace it with built-in replace mechanism

    if source_path.endswith('.yaml') or source_path.endswith('.env'):
        with open(source_path, "r") as input_file:
            content = input_file.read()
        for key, value in PARAMETERS.items():
            string_to_replace = '{{ ' + key + ' }}'
            content = content.replace(string_to_replace, value)
        with open(destination_path, "w") as output_file:
            output_file.write(content)


PARAMETERS = {}


SERVICE_ACCOUNTS = [
    dict(keyfile='gcp_bigtable.json',
         account_name='gcp-bigtable-account',
         account_description='Bigtable account',
         roles=['roles/bigtable.admin'],
         services=['bigtable.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_cloudsql.json',
         account_name='gcp-cloudsql-account',
         account_description='CloudSQL account',
         roles=['roles/cloudsql.admin'],
         services=['sqladmin.googleapis.com', 'sql-component.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_compute.json',
         account_name='gcp-compute-account',
         account_description='Compute account',
         roles=['roles/compute.instanceAdmin',
                'roles/compute.instanceAdmin.v1',
                'roles/iam.serviceAccountUser'],
         services=['compute.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_function.json',
         account_name='gcp-function-account',
         account_description='Google Cloud Function account',
         roles=['roles/source.reader', 'roles/cloudfunctions.developer'],
         services=['cloudfunctions.googleapis.com'],
         appspot_service_account_impersonation=True),
    dict(keyfile='gcp_spanner.json',
         account_name='gcp-spanner-account',
         account_description='Google Cloud Spanner account',
         roles=['roles/spanner.admin'],
         services=['spanner.googleapis.com'],
         appspot_service_account_impersonation=False),
]

KEYRING = 'incubator-airflow'
KEY = 'service_accounts_crypto_key'


def create_keyring_and_keys():
    print()
    print("Creating keyring and keys ... ")
    print()
    output = subprocess.check_output(['gcloud', 'kms', 'keyrings', 'list',
                                      '--filter={}'.format(KEYRING),
                                      '--format=json',
                                      '--project={}'.format(project_id),
                                      '--location=global'])
    keyrings = json.loads(output)
    if keyrings and len(keyrings) > 0:
        print("The keyring is already created. Not creating it again!")
    else:
        subprocess.call(['gcloud', 'kms', 'keyrings', 'create', KEYRING,
                         '--project={}'.format(project_id),
                         '--location=global'])
        subprocess.call(['gcloud', 'kms', 'keys', 'create', KEY,
                         '--project={}'.format(project_id),
                         '--keyring={}'.format(KEYRING),
                         '--purpose=encryption',
                         '--location=global'])


def encrypt_value(value):
    return subprocess.check_output(
        [
            '/bin/bash', '-c',
            'echo -n {} | '
            'gcloud kms encrypt --plaintext-file=- --ciphertext-file=- '
            '--location=global --keyring={} '
            '--key={} --project={} | base64'.format(value, KEYRING, KEY, project_id)
        ]
    ).decode()


def encrypt_file(file):
    print("Encrypting file {}".format(file))
    return subprocess.call(
        [
            'gcloud', 'kms', 'encrypt',
            '--plaintext-file={}'.format(file),
            '--ciphertext-file={}.enc'.format(file),
            '--location=global',
            '--keyring={}'.format(KEYRING),
            '--key={}'.format(KEY),
            '--project={}'.format(project_id)
        ]
    )


def assign_service_account_appspot_role_to_service_account(service_account_email):
    print("Assigning default appspot account {}@appspot.gserviceaccount.com "
          "service account user role for service account {}".
          format(project_id, service_account_email))
    with open(os.devnull, 'w') as FNULL:
        return subprocess.call(
            [
                'gcloud', 'iam', 'service-accounts', 'add-iam-policy-binding',
                '{}@appspot.gserviceaccount.com'.format(project_id),
                '--project={}'.format(project_id),
                '--member', 'serviceAccount:{}'.format(service_account_email),
                '--role', 'roles/iam.serviceAccountUser'
            ], stdout=FNULL
        )


def assign_role_to_service_account(service_account_email, role):
    print("Assigning {} role to {}".format(role, service_account_email))
    with open(os.devnull, 'w') as FNULL:
        return subprocess.call(
            [
                'gcloud', 'projects', 'add-iam-policy-binding', project_id,
                '--member', 'serviceAccount:{}'.format(service_account_email),
                '--role', role
            ], stdout=FNULL
        )


def enable_service(service):
    print("Enabling service {}".format(service))
    subprocess.call(['gcloud', 'services', 'enable',
                     service,
                     '--project={}'.format(project_id)])


def create_all_service_accounts():
    print()
    print("Creating all service accounts ... ")
    print()
    for service_account in SERVICE_ACCOUNTS:
        keyfile = service_account['keyfile']
        account_name = service_account['account_name']
        service_account_display_name = service_account['account_description']
        roles = service_account['roles']
        services = service_account['services']
        appspot_service_account_impersonation = \
            service_account['appspot_service_account_impersonation']
        service_account_email = '{}@{}.iam.gserviceaccount.com'.format(
            account_name, project_id)
        key_file = os.path.join(TARGET_DIR, "keys", keyfile)
        with open(os.devnull, 'w') as FNULL:
            subprocess.call(['gcloud', 'iam', 'service-accounts',
                             'delete', service_account_email,
                             '--project={}'.format(project_id),
                             '--quiet'], stderr=FNULL)
            subprocess.call(['gcloud', 'iam', 'service-accounts',
                             'create', account_name,
                             '--display-name',
                             service_account_display_name,
                             '--project={}'.format(project_id)])
            subprocess.call(['gcloud', 'iam', 'service-accounts', 'keys',
                             'create', key_file,
                             '--iam-account', service_account_email,
                             '--project={}'.format(project_id)])
        encrypt_file(key_file)
        for service in services:
            enable_service(service)
        for role in roles:
            assign_role_to_service_account(service_account_email, role)
        if appspot_service_account_impersonation:
            assign_service_account_appspot_role_to_service_account(service_account_email)


def create_and_push_google_cloud_repository(directory, repo_name):
    subprocess.call(["gcloud", "source", "repos", "create", repo_name,
                     '--project={}'.format(project_id)])
    subprocess.call(['git', 'config', '--global',
                     'credential.https://source.developers.google.com.helper'
                     'gcloud.sh'], cwd=directory)
    subprocess.call(['git', 'init'], cwd=directory)
    subprocess.call(['git', 'remote', 'add', 'google',
                     'https://source.developers.google.com/p/{}/r/{}'.format(
                         project_id, repo_name)], cwd=directory)
    subprocess.call(['git', 'add', '.'], cwd=directory)
    subprocess.call(['git', 'commit', '-m', 'Initial commit of bootstrapped repository'],
                    cwd=directory)
    subprocess.call(['git', 'push', '--all', 'google'], cwd=directory)


if __name__ == '__main__':

    if sys.version_info < (3, 0):
        sys.stdout.write("Sorry, bootstrap requires Python 3.x\n")
        sys.exit(1)

    parser = argparse.ArgumentParser(description='Bootstraps {} repository.'.
                                     format(CONFIG_REPO_NAME))
    parser.add_argument('--workspace', '-w', required=True,
                        help='Path to the workspace where the dir should be bootstrapped')
    parser.add_argument('--gcp-project-id', '-p', required=True,
                        help='GCP project id')

    args = parser.parse_args()

    TARGET_DIR = check_if_config_exists(args.workspace)

    project_id = args.gcp_project_id

    confirm = input("\nBootstrapping project '{}'. \n\n"
                    "NOTE! This is a destructive operation if you already "
                    "bootstrapped it before. \n\nAre you sure (y/n) ?: ".
                    format(project_id))
    if confirm != 'y':
        sys.exit(1)

    enable_service('cloudkms.googleapis.com')
    enable_service('cloudbuild.googleapis.com')

    create_keyring_and_keys()

    PARAMETERS['GCP_PROJECT_ID'] = project_id
    password = input("Password to use for Postgres and MySql database: ")

    encrypted_password = encrypt_value(password)

    postgres_ip = input("IP of the Postgres database: ")
    mysql_ip = input("IP of the MySQL database: ")

    slack_hook = input('Provide slack hook to post Cloud Build status - usually '
                       'https://hooks.slack.com/services/...'
                       '(ENTER will skip Slack notification): ')

    github_organization = input('Provide your GitHub user/organization name:')

    PARAMETERS['GITHUB_ORGANIZATION'] = github_organization
    PARAMETERS['ENCRYPTED_PASSWORD'] = encrypted_password
    PARAMETERS['POSTGRES_IP'] = postgres_ip
    PARAMETERS['MYSQL_IP'] = mysql_ip

    if not slack_hook:
        IGNORE_SLACK = True
    shutil.copytree(BOOTSTRAP_CONFIG_DIR, TARGET_DIR,
                    ignore=ignore_dirs, copy_function=copy_files)

    create_all_service_accounts()

    create_and_push_google_cloud_repository(TARGET_DIR, CONFIG_REPO_NAME)
