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
"""Writes GCP Connection to the airflow db."""
import json
import os
import sys

from airflow import models
from airflow import settings

KEYPATH_EXTRA = 'extra__google_cloud_platform__key_path'
SCOPE_EXTRA = 'extra__google_cloud_platform__scope'
PROJECT_EXTRA = 'extra__google_cloud_platform__project'

key_file_name = os.environ.get('GCP_SERVICE_ACCOUNT_KEY_NAME')
home_dir = os.path.expanduser('~')
full_key_path = os.path.join(home_dir,
                             "airflow-breeze-config",
                             "keys",
                             key_file_name)
if not os.path.isfile(full_key_path):
    print()
    print('The key file ' + full_key_path + ' is missing!')
    print()
    sys.exit(1)

session = settings.Session()
try:
    # noinspection PyUnresolvedReferences
    conn = session.query(models.Connection).filter(
      models.Connection.conn_id == 'google_cloud_default')[0]
    extras = conn.extra_dejson
    extras[KEYPATH_EXTRA] = full_key_path
    print('Setting GCP key file to ' + full_key_path)
    extras[SCOPE_EXTRA] = 'https://www.googleapis.com/auth/cloud-platform'
    extras[PROJECT_EXTRA] = sys.argv[1]
    conn.extra = json.dumps(extras)
    session.commit()
except BaseException as e:
    print('session error' + str(e))
    session.rollback()
    raise
finally:
    session.close()
