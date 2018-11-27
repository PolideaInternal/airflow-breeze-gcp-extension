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
"""Decrypts all encrypted variables from environment"""
import os
import subprocess
import sys

ENCRYPTED_SUFFIX = "_ENCRYPTED"

if __name__ == '__main__':
    project_id = sys.argv[1]
    for key, val in os.environ.items():
        if key.endswith(ENCRYPTED_SUFFIX):
            decrypted_key = key[:-len(ENCRYPTED_SUFFIX)]
            decrypted_val = subprocess.check_output(
                ['bash', '-c',
                 'echo -n "{}" | base64 --decode | '
                 'gcloud kms decrypt --plaintext-file=- '
                 '--ciphertext-file=- --location=global '
                 '--keyring=incubator-airflow '
                 '--project={} '
                 '--key=service_accounts_crypto_key'.format(val, project_id)])
            print("{}={}".format(decrypted_key, decrypted_val))
