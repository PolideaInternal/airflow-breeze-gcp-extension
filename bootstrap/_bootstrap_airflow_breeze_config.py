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
"""Bootstraps an empty config project"""
import json
import random
import string
import tempfile

import subprocess
import sys

import argparse
import os
import shutil
from os.path import dirname, basename

TEMPLATE_PREFIX = "TEMPLATE-"

MY_DIR = dirname(__file__)

BOOTSTRAP_CONFIG_DIR = os.path.join(MY_DIR, "config")
HELLO_WORLD_SOURCE_DIR = os.path.join(MY_DIR, "hello-world")
TEST_FILES_DIR = os.path.join(MY_DIR, "test-files")
BUILD_LIFECYCLE_RULE_FILE = os.path.join(MY_DIR, "build_lifecycle_rule.json")

CONFIG_REPO_NAME = "airflow-breeze-config"
CONFIG_DIR_NAME = "config"
HELLO_WORLD_REPO_NAME = "hello-world"

TARGET_DIR = ''

IGNORE_SLACK = False
KEYRING = 'airflow'
KEY = 'airflow_crypto_key'
BUILD_BUCKET_SUFFIX = '-builds'
TEST_BUCKET_SUFFIX = '-tests'

TEST_SUITES = ['python27', 'python35', 'python36']

VARIABLES = {}


def get_config_dir(workspace_dir):
    global TARGET_DIR
    TARGET_DIR = os.path.join(workspace_dir, CONFIG_DIR_NAME)


def assert_config_directory_does_not_exist():
    if os.path.isdir(TARGET_DIR):
        raise Exception("Configuration folder {} already exists. Remove it to "
                        "bootstrap it from scratch".format(TARGET_DIR))


def assert_config_directory_exists():
    if not os.path.isdir(TARGET_DIR):
        raise Exception("Configuration folder {} does not exist. Please "
                        "re-run run_environment.sh to check it out".format(TARGET_DIR))


def ignore_dirs(src, names):
    ignored = []
    if IGNORE_SLACK and basename(src) == 'config' and 'notifications' in names:
        ignored.append('notifications')
    return ignored


def copy_file(source_path, destination_path):
    if TEMPLATE_PREFIX in destination_path:
        destination_path = destination_path.replace(TEMPLATE_PREFIX, "")
    print('Copying file {} -> {}'.format(
        source_path, destination_path))
    shutil.copy2(source_path, destination_path)

    # We do not use Jinja2 or another templating system because we want to make
    # bootstrapping works without external dependencies. Also built-in templating
    # is not good enough because it uses $variable syntax that would clash with
    # Bash substitution we use in a number of places. In order to avoid escaping
    # The '$' we use Jinja2 form of template variables '{{ VARIABLE }}' or
    # '{{VARIABLE}}'. Note strict single spaces or lack of them!

    if os.path.isfile(source_path):
        with open(source_path, "r") as input_file:
            content = input_file.read()
        for key, value in VARIABLES.items():
            string_to_replace1 = '{{ ' + key + ' }}'
            content = content.replace(string_to_replace1, value)
            string_to_replace2 = '{{' + key + '}}'
            content = content.replace(string_to_replace2, value)
        with open(destination_path, "w") as output_file:
            output_file.write(content)


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
    dict(keyfile='gcp_gcs.json',
         account_name='gcp-storage-account',
         account_description='Google Cloud Storage account',
         roles=['roles/storage.admin'],
         services=['storage-api.googleapis.com', 'storage-component.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_ai.json',
         account_name='gcp-ai-account',
         account_description='Google Cloud AI account',
         roles=['roles/storage.admin'],
         services=['storage-api.googleapis.com', 'storage-component.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_gcs_transfer.json',
         account_name='gcp-storage-transfer-account',
         account_description='Google Cloud Storage Transfer account',
         roles=['roles/editor'],
         services=['storage-api.googleapis.com', 'storage-component.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_cloud_build.json',
         account_name='gcp-cloud-build-account',
         account_description='Google Cloud Build account',
         roles=['roles/cloudbuild.builds.editor', 'roles/source.admin', 'roles/storage.admin'],
         services=['storage-api.googleapis.com',
                   'storage-component.googleapis.com',
                   'sourcerepo.googleapis.com',
                   'cloudbuild.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_dataproc.json',
         account_name='gcp-dataproc-account',
         account_description='Google Cloud Dataproc account',
         roles=['roles/editor'],
         services=['dataproc.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_automl.json',
         account_name='gcp-automl-account',
         account_description='Google Cloud AutoML account',
         roles=['roles/automl.admin'],
         services=['automl.googleapis.com'],
         appspot_service_account_impersonation=False),
    dict(keyfile='gcp_bigquery.json',
         account_name='gcp-bigquery-account',
         account_description='Google Cloud BigQuery account',
         roles=['roles/bigquery.admin', 'roles/storage.objectAdmin', 'roles/bigquery.tables.get'],
         services=['bigquery.googleapis.com']),
]


def logged_call(command, cwd=os.getcwd(), stderr=None, stdout=None):
    print()
    print("> Running command: '{}' in directory {}".format(' '.join(command), cwd))
    print()
    return subprocess.call(command, cwd=cwd, stderr=stderr, stdout=stdout)


def create_keyring_and_keys():
    print()
    print("Creating keyring and keys ... ")
    print()
    output = subprocess.check_output(['gcloud', 'kms', 'keyrings', 'list',
                                      '--filter={}'.format(KEYRING),
                                      '--format=json',
                                      '--project={}'.format(project_id),
                                      '--location=global']).decode('utf-8')
    keyrings = json.loads(output)
    if keyrings and len(keyrings) > 0:
        print("The keyring is already created. Not creating it again!")
    else:
        logged_call(['gcloud', 'kms', 'keyrings', 'create', KEYRING,
                     '--project={}'.format(project_id),
                     '--location=global'])
        logged_call(['gcloud', 'kms', 'keys', 'create', KEY,
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
    ).decode("utf-8").strip()


def decrypt_value(value):
    return subprocess.check_output(
        [
            '/bin/bash', '-c',
            'echo -n {} | base64 --decode | '
            'gcloud kms decrypt --plaintext-file=- --ciphertext-file=- '
            '--location=global --keyring={} '
            '--key={} --project={}'.format(value, KEYRING, KEY, project_id)
        ]
    ).decode("utf-8")

def encrypt_file(file):
    print("Encrypting file {}".format(file))
    return logged_call(
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


def bind_service_account_user_role_for_appspot_account(service_account_email):
    print("Binding default appspot account {}@appspot.gserviceaccount.com with "
          "service account user role for service account {}".
          format(project_id, service_account_email))
    with open(os.devnull, 'w') as FNULL:
        return logged_call(
            [
                'gcloud', 'iam', 'service-accounts', 'add-iam-policy-binding',
                '{}@appspot.gserviceaccount.com'.format(project_id),
                '--project={}'.format(project_id),
                '--member', 'serviceAccount:{}'.format(service_account_email),
                '--role', 'roles/iam.serviceAccountUser'
            ], stdout=FNULL
        )


def add_default_acl_to_bucket(bucket_name, role, service_account):
    print("Adding default ACL for service account {} of role {} in bucket {}".
          format(service_account, role, bucket_name))
    return logged_call(
        [
            'gsutil', 'defacl', 'ch', '-u',
            '{}:{}'.format(service_account, role),
            'gs://{}'.format(bucket_name)
        ]
    )


def grant_storage_role_to_service_account(bucket_name, role, service_account):
    print("Granting the service account {} "
          "role storage.{} to bucket {}".
          format(service_account, role, bucket_name))
    return logged_call(
        [
            'gsutil', 'iam', 'ch',
            'serviceAccount:{}:{}'.
            format(service_account, role),
            'gs://{}'.format(bucket_name)
        ]
    )


def bind_role_to_service_account(service_account_email, role):
    print("Assigning {} role to {}".format(role, service_account_email))
    with open(os.devnull, 'w') as FNULL:
        return logged_call(
            [
                'gcloud', 'projects', 'add-iam-policy-binding', project_id,
                '--member', 'serviceAccount:{}'.format(service_account_email),
                '--role', role
            ], stdout=FNULL
        )


def bind_roles_to_cloudbuild():
    project_number = subprocess.check_output(
        [
            'gcloud', 'projects', 'describe', project_id,
            '--format', 'value(projectNumber)'
        ]
    ).decode("utf-8").strip()
    bind_service_account_user_role_for_appspot_account(
        '{}@cloudbuild.gserviceaccount.com'.format(project_number))
    logged_call([
        'gcloud', 'kms', 'keys', 'add-iam-policy-binding',
        KEY, '--location=global', '--keyring={}'.format(KEYRING),
        '--project={}'.format(project_id),
        '--member=serviceAccount:{}@cloudbuild.gserviceaccount.com'.
        format(project_number),
        '--role=roles/cloudkms.cryptoKeyDecrypter'
    ])
    bind_role_to_service_account("{}@cloudbuild.gserviceaccount.com"
                                 .format(project_number),
                                 'roles/cloudfunctions.developer')


def enable_service(service):
    print("Enabling service {}".format(service))
    logged_call(['gcloud', 'services', 'enable',
                 service,
                 '--project={}'.format(project_id)])


def create_all_service_accounts(recreate_service_accounts):
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
            account_exists = logged_call(['gcloud', 'iam', 'service-accounts',
                                          'describe', service_account_email,
                                          '--project={}'.format(project_id)]) == 0
            if account_exists and recreate_service_accounts:
                logged_call(['gcloud', 'iam', 'service-accounts',
                             'delete', service_account_email,
                             '--project={}'.format(project_id),
                             '--quiet'], stderr=FNULL)
                account_exists = False
            if not account_exists:
                account_created = logged_call(['gcloud', 'iam', 'service-accounts',
                                               'create', account_name,
                                               '--display-name',
                                               service_account_display_name,
                                               '--project={}'.format(project_id)]) == 0
                if account_created:
                    logged_call(['gcloud', 'iam', 'service-accounts', 'keys',
                                 'create', key_file,
                                 '--iam-account', service_account_email,
                                 '--project={}'.format(project_id)])
        encrypt_file(key_file)
        for service in services:
            enable_service(service)
        for role in roles:
            bind_role_to_service_account(service_account_email, role
                                         )
        if appspot_service_account_impersonation:
            bind_service_account_user_role_for_appspot_account(service_account_email)


def configure_google_cloud_source_repository_helper():
    logged_call(['git', 'config', '--global',
                 'credential.https://source.developers.google.com.helper'
                 'gcloud.sh'])


def create_google_cloud_repository(directory, repo_name):
    logged_call(["gcloud", "source", "repos", "create", repo_name,
                 '--project={}'.format(project_id)])
    logged_call(['git', 'init'], cwd=directory)
    logged_call(['git', 'remote', 'add', 'origin',
                 'https://source.developers.google.com/p/{}/r/{}'.format(
                     project_id, repo_name)], cwd=directory)


def commit_and_push_google_cloud_repository(directory, initial=True):
    logged_call(['git', 'add', '.'], cwd=directory)
    logged_call(['git', 'commit', '-m',
                 'Initial commit of bootstrapped repository' if initial
                 else 'Updating service keys and configuration'],
                cwd=directory)
    logged_call(['git', 'push', '--set-upstream', 'origin', 'master'], cwd=directory)


def create_bucket(bucket_name, recreate_bucket, read_all,
                  files_dir=None,
                  lifecycle_rule=None):
    if recreate_bucket:
        logged_call(["gsutil", "-m", "rm", '-R', '-a', "gs://{}".format(bucket_name)])
    logged_call(["gsutil", "mb", '-c', 'multi_regional', '-p', project_id,
                 "gs://{}".format(bucket_name)])
    if read_all:
        logged_call(["gsutil", "iam", "ch", "allUsers:objectViewer",
                     "gs://{}".format(bucket_name)])
    if files_dir:
        for file in os.listdir(files_dir):
            if os.path.isfile(os.path.join(files_dir, file)):
                logged_call(['gsutil', 'cp', file, "gs://{}".format(bucket_name)],
                            cwd=files_dir)
    if lifecycle_rule:
        logged_call(['gsutil', 'lifecycle', 'set', lifecycle_rule,
                     "gs://{}".format(bucket_name)], cwd=MY_DIR)


def start_section(section):
    print()
    print("#" * 100)
    print("#  " + section)
    print("#" * 100)


def end_section():
    print("#" * 100)
    print()


def read_parameter(key, description):
    global VARIABLES
    default_value = VARIABLES.get(key)
    if default_value:
        description += '[{}] ?: '.format(default_value)
    else:
        description += '?: '
    res = input(description)
    if res == '':
        VARIABLES[key] = default_value
    else:
        VARIABLES[key] = res


def get_random_password():
    random.seed()
    return ''.join(random.choice(string.ascii_uppercase + string.digits)
                   for _ in range(10))


def read_manual_parameters(regenerate_passwords):
    global IGNORE_SLACK
    VARIABLES['GCP_PROJECT_ID'] = project_id
    if not VARIABLES.get('AIRFLOW_REPO_NAME'):
        VARIABLES['AIRFLOW_REPO_NAME'] = 'airflow'
    if regenerate_passwords:
        VARIABLES['GCSQL_MYSQL_PASSWORD_ENCRYPTED'] = encrypt_value(get_random_password())
        VARIABLES['GCSQL_POSTGRES_PASSWORD_ENCRYPTED'] = encrypt_value(get_random_password())
    read_parameter('BUILD_BUCKET_SUFFIX', 'Suffix of the GCS bucket where build '
                   'artifacts are stored (bucket name: {}<SUFFIX>)'.format(project_id))
    read_parameter('TEST_BUCKET_SUFFIX', 'Suffix of the GCS bucket where build '
                   'test files are stored (bucket name: {}<SUFFIX>-<PYTHON_VERSION>)'.format(project_id))
    read_parameter('AIRFLOW_BREEZE_GITHUB_ORGANIZATION',
                   'Your GitHub user/organization name')
    read_parameter('AIRFLOW_REPO_NAME',
                   'Name of your repository in your user/organization')
    setup_slack_notifications = input("Setup Slack notifications ? (y/n) [y]")
    if setup_slack_notifications == 'y' or setup_slack_notifications == 'Y' \
            or setup_slack_notifications == '':
        read_parameter('SLACK_HOOK', 'Slack hook to post Cloud Build status - usually '
                       'https://hooks.slack.com/services/... ')
        VARIABLES['SLACK_HOOK_ENCRYPTED'] = encrypt_value(VARIABLES.get('SLACK_HOOK'))
    else:
        IGNORE_SLACK = True
    setup_aws_credentials = input("Setup AWS credentials ? (y/n) [n]")
    if setup_aws_credentials == 'y' or setup_aws_credentials == 'Y':
        read_parameter('AWS_ACCESS_KEY_ID', 'Access key ID:')
        read_parameter('AWS_SECRET_ACCESS_KEY', 'Secret access key:')
        read_parameter('AWS_DEFAULT_REGION', 'Default region:')
        VARIABLES['AWS_ACCESS_KEY_ID_ENCRYPTED'] = encrypt_value(VARIABLES.get('AWS_ACCESS_KEY_ID'))
        VARIABLES['AWS_SECRET_ACCESS_KEY_ENCRYPTED'] = encrypt_value(VARIABLES.get('AWS_SECRET_ACCESS_KEY'))


def copy_configuration_directory():
    if not os.path.isdir(TARGET_DIR):
        shutil.copytree(BOOTSTRAP_CONFIG_DIR, TARGET_DIR,
                        ignore=ignore_dirs, copy_function=copy_file)
    else:
        # overwrite files in the config dir
        for file in os.listdir(BOOTSTRAP_CONFIG_DIR):
            if os.path.isfile(os.path.join(BOOTSTRAP_CONFIG_DIR, file)):
                copy_file(os.path.join(BOOTSTRAP_CONFIG_DIR, file),
                          os.path.join(TARGET_DIR, file))
        if not os.path.isdir(os.path.join(TARGET_DIR, 'notifications')):
            # only copy notifications folder if not already copied!
            shutil.copytree(os.path.join(BOOTSTRAP_CONFIG_DIR, "notifications"),
                            os.path.join(TARGET_DIR, "notifications"),
                            ignore=ignore_dirs, copy_function=copy_file)
        else:
            # Otherwise loop all notification subdirs and copy them as needed
            for directory in os.listdir(os.path.join(BOOTSTRAP_CONFIG_DIR,
                                                     'notifications')):
                source_notification_dir = os.path.join(BOOTSTRAP_CONFIG_DIR,
                                                       "notifications", directory)
                target_notification_dir = os.path.join(TARGET_DIR,
                                                       "notifications", directory)
                if IGNORE_SLACK and directory == 'slack':
                    continue
                if not os.path.isdir(target_notification_dir):
                    # Copy the whole dir if it does not exist
                    shutil.copytree(source_notification_dir, target_notification_dir,
                                    ignore=ignore_dirs, copy_function=copy_file)
                else:
                    # Overwrite files in notifications folder if already exists
                    for file in os.listdir(source_notification_dir):
                        if os.path.isfile(os.path.join(source_notification_dir, file)):
                            copy_file(os.path.join(source_notification_dir, file),
                                      os.path.join(target_notification_dir, file))


def encrypt_notification_configuration_files():
    for root, dirs, files in os.walk(os.path.join(TARGET_DIR)):
        for file in files:
            if file == "secret.variables.yaml":
                encrypt_file(os.path.join(root, file))


def create_and_configure_buckets():
    build_bucket = "{}{}".format(project_id, BUILD_BUCKET_SUFFIX)
    test_bucket = "{}{}".format(project_id, TEST_BUCKET_SUFFIX)
    create_bucket(build_bucket,
                  recreate_bucket=args.recreate_project, read_all=True,
                  lifecycle_rule=BUILD_LIFECYCLE_RULE_FILE)
    gcp_cloudsql_service_account = "gcp-cloudsql-account@{}.iam.gserviceaccount.com". \
        format(project_id)
    for test_suite in TEST_SUITES:
        test_bucket_full_name = test_bucket + "-" + test_suite[-2:]
        create_bucket(test_bucket_full_name,
                      recreate_bucket=args.recreate_project, read_all=False,
                      files_dir=TEST_FILES_DIR)
        grant_storage_role_to_service_account(
            test_bucket_full_name,
            "admin",
            gcp_cloudsql_service_account)
    grant_storage_role_to_service_account(
        build_bucket,
        "objectCreator",
        "{}@appspot.gserviceaccount.com".format(project_id))


if __name__ == '__main__':

    if sys.version_info < (3, 0):
        sys.stdout.write("Sorry, bootstrap requires Python 3.x\n")
        sys.exit(1)

    parser = argparse.ArgumentParser(description='Bootstraps GCP project for '
                                                 'Airflow Breeze.')
    parser.add_argument('--workspace', '-w', required=True,
                        help='Path to the workspace')
    parser.add_argument('--gcp-project-id', '-p', required=True,
                        help='GCP project id')
    parser.add_argument('--recreate-project', '-r', action='store_true',
                        help='Recreates all service accounts, keys and buckets')

    args = parser.parse_args()

    project_id = args.gcp_project_id

    create_new_config_repo = logged_call(['gcloud', 'source', 'repos', 'describe',
                                          '--project', project_id,
                                          CONFIG_REPO_NAME]) != 0

    get_config_dir(args.workspace)

    VARIABLES['BUILD_BUCKET_SUFFIX'] = BUILD_BUCKET_SUFFIX
    VARIABLES['TEST_BUCKET_SUFFIX'] = TEST_BUCKET_SUFFIX

    if create_new_config_repo:
        assert_config_directory_does_not_exist()
        confirm = input("\nBootstrapping project '{}' from scratch. \n\n"
                        "This will create {} repository!"
                        "\n\nAre you sure (y/n) ?: ".
                        format(project_id, CONFIG_REPO_NAME))
        # force re-creation of objects
        args.recreate_project = True
    else:
        assert_config_directory_exists()
        # Read current values from environment to retain their values
        VARIABLES.update(os.environ)
        if VARIABLES.get('SLACK_HOOK_ENCRYPTED'):
            try:
                VARIABLES['SLACK_HOOK'] = decrypt_value(VARIABLES.get('SLACK_HOOK_ENCRYPTED'))
            except subprocess.CalledProcessError:
                read_parameter('SLACK_HOOK', "Could not decrypt SLACK_HOOK. "
                                             "Provide new value!")
        if args.recreate_project:
            confirm = input("\nThe project '{}' is already bootstrapped.\n\n"
                            "The {} repository is already created and checked out.\n\n"
                            "If you answer y, the script will RECREATE THE PROJECT. \n" 
                            "All services accounts will be recreated, passwords "
                            "and configuration files will be regenerated "
                            "(retaining existing values)\n\n "
                            "This is useful in case you want to recreate all secrets."
                            "\n\nAre you sure (y/n) ?: ".
                            format(project_id, CONFIG_REPO_NAME))
        else:
            confirm = input("\nThe project '{}' is already bootstrapped.\n\n"
                            "The {} repository is already created and checked out.\n\n"
                            "If you answer y, the script will "
                            "re-enable all services and \n "
                            "regenerate configuration files "
                            "(retaining existing values)\n\n "
                            "This is useful in case you added new services or you "
                            "want to upgrade to latest notification code."
                            "\n\nAre you sure (y/n) ?: ".
                            format(project_id, CONFIG_REPO_NAME))
    if confirm != 'y' and confirm != 'Y':
        sys.exit(1)

    start_section("Provide manual parameters for the bootstrap process of {}".
                  format(project_id))
    read_manual_parameters(regenerate_passwords=args.recreate_project)
    end_section()

    start_section("Enabling KMS and Cloud Build for project {}".format(project_id))
    enable_service('cloudkms.googleapis.com')
    enable_service('cloudbuild.googleapis.com')
    end_section()

    start_section('Binding roles to Cloud Build service account')
    bind_roles_to_cloudbuild()
    end_section()

    start_section("Creating keyring and key for encryption for project {}".
                  format(project_id))
    create_keyring_and_keys()
    end_section()

    start_section("Copying files (with overwritten values) in configuration dir")
    copy_configuration_directory()
    end_section()

    start_section("Encrypting secret_variables.yaml files in notifications directory")
    encrypt_notification_configuration_files()
    end_section()

    start_section("Creating all service accounts for project {}".format(project_id))
    create_all_service_accounts(recreate_service_accounts=args.recreate_project)
    end_section()

    start_section("Creating build and test buckets for project {}".format(project_id))

    create_and_configure_buckets()
    end_section()

    start_section("Configuring Cloud Source Repository authentication")
    configure_google_cloud_source_repository_helper()
    end_section()

    if create_new_config_repo:
        start_section("Creating {} and {} projects in Google Cloud "
                      "Repository for project {}".
                      format(CONFIG_REPO_NAME, HELLO_WORLD_REPO_NAME, project_id))
        create_google_cloud_repository(TARGET_DIR, CONFIG_REPO_NAME)
        commit_and_push_google_cloud_repository(TARGET_DIR, initial=True)
        hello_world_dir = tempfile.mkdtemp()
        # Delete so that copytree can work
        os.rmdir(hello_world_dir)
        shutil.copytree(HELLO_WORLD_SOURCE_DIR, hello_world_dir)
        create_google_cloud_repository(hello_world_dir, HELLO_WORLD_REPO_NAME)
        commit_and_push_google_cloud_repository(hello_world_dir, initial=True)
        shutil.rmtree(hello_world_dir)
        end_section()

    start_section("Pushing files to {} in Google Cloud Repository for project {}".format(
                  CONFIG_REPO_NAME, project_id))
    logged_call(['git', 'status'], cwd=TARGET_DIR)
    logged_call(['git', 'diff'], cwd=TARGET_DIR)
    res = input("Confirm adding, committing and pushing to "
                "the airflow-breeze-config repo [y/n] ? ")
    if res == 'y' or res == 'Y':
        commit_and_push_google_cloud_repository(TARGET_DIR,
                                                initial=create_new_config_repo)
    end_section()
