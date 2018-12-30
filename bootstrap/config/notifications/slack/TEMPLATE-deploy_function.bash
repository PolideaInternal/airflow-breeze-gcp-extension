#!/usr/bin/env bash
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd ${MY_DIR}
for file in index.js package.json package-lock.json
do
    ln -sf ${MY_DIR}/../../../../../notifications/slack/${file}
done
cat variables.yaml secret.variables.yaml >all.variables.yaml
PROJECT_ID=$(cat all.variables.yaml | grep "^PROJECT_ID:" | awk '{print $2}')
gcloud beta functions deploy \
    --env-vars-file=all.variables.yaml \
    slack_notify \
    --stage-bucket polidea-airflow-builds --trigger-topic cloud-builds \
    --runtime nodejs8 --project ${PROJECT_ID}
popd
