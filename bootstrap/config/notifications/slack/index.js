const IncomingWebhook = require('@slack/client').IncomingWebhook;
const GCS_BUCKET = process.env.GCS_BUCKET
const REPO_NAME = process.env.REPO_NAME

const webhook = new IncomingWebhook(process.env.SLACK_HOOK);
const test_suites = process.env.AIRFLOW_BREEZE_TEST_SUITES.split(" ")

// subscribe is the main function called by Cloud Functions.
module.exports.slack_notify = (event, callback) => {
    const build = eventToBuild(event.data.data);

// Skip if the current status is not in the status list.
// Add additional statues to list if you'd like:
// QUEUED, WORKING, SUCCESS, FAILURE,
// INTERNAL_ERROR, TIMEOUT, CANCELLED
    const status = ['SUCCESS', 'FAILURE', 'INTERNAL_ERROR', 'TIMEOUT'];
    console.log("#########################################")
    console.log(JSON.stringify(build, null, 4))
    console.log("#########################################")
    console.log("#########################################")
    console.log(JSON.stringify(build))
    console.log("#########################################")

    if (status.indexOf(build.status) === -1) {
        console.log(`Skipping slack notification as ${status} is wrong`)
        return callback();
    }
    if (build.substitutions.REPO_NAME !== REPO_NAME) {
        console.log(`Skipping slack notification as ${build.substitutions.REPO_NAME} != ${REPO_NAME}`)
        return callback();
    }
    // Send message to Slack.
    const message = createSlackMessage(build);
    webhook.send(message, callback);
};

// eventToBuild transforms pubsub event message to a build object.
const eventToBuild = (data) => {
    return JSON.parse(new Buffer(data, 'base64').toString());
}

// createSlackMessage create a message from a build object.
const createSlackMessage = (build) => {
    var attachments = [
        {
            title: 'Summary page',
            title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/index.html`
        },
        {
            title: 'Google Cloud Build page',
            title_link: `https://console.cloud.google.com/cloud-build/builds/${build.id}?project=${build.projectId}`
        },
        {
            title: 'Airflow logs in GCS bucket',
            title_link: `https://console.cloud.google.com/storage/browser/${GCS_BUCKET}/${build.id}/logs/?project=${build.projectId}`
        },
        {
            title: 'Stackdriver logs',
            title_link: `https://console.cloud.google.com/logs/viewer?authuser=0&project=${build.projectId}&minLogLevel=0&expandAll=false&resource=build%2Fbuild_id%2F${build.id}`
        },
        {
            title: 'Generated documentation',
            title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/docs/index.html`
        }
    ]

    let i;
    for (i = 0; i < test_suites.length; i++) {
        attachments.push({
            title: `${test_suites[i]} test results`,
            title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/tests/${test_suites[i]}.xml.html`
        })
    }

    return {
        text: `Build for repo '${build.substitutions.REPO_NAME}' status ${build.status} - \`${build.id}\` `,
        mrkdwn: true,
        attachments: attachments
    }
}
