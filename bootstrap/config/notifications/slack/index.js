const {Storage} = require('@google-cloud/storage');
const {PubSub} = require('@google-cloud/pubsub');
let ps;

const IncomingWebhook = require('@slack/client').IncomingWebhook;

const GCS_BUCKET = process.env.GCS_BUCKET;
const REPO_NAME = process.env.REPO_NAME;
const PROJECT_ID = process.env.PROJECT_ID;

const webhook = new IncomingWebhook(process.env.SLACK_HOOK);
const test_suites = process.env.AIRFLOW_BREEZE_TEST_SUITES.split(" ");

const storage = new Storage({
    projectId: PROJECT_ID,
});

const bucket = storage.bucket(GCS_BUCKET);

// subscribe is the main function called by Cloud Functions.
module.exports.slack_notify = async (data, context) => {
    ps = ps || new PubSub();
    try {
        const build = JSON.parse(Buffer.from(data.data, 'base64').toString());
        const topicName = context.resource.name;
        const topic = ps.topic(topicName);
        const metadata = await topic.getMetadata()[0];
        // Skip if the current status is not in the status list.
        // Add additional statues to list if you'd like:
        // QUEUED, WORKING, SUCCESS, FAILURE,
        // INTERNAL_ERROR, TIMEOUT, CANCELLED
        const status = ['SUCCESS', 'FAILURE', 'INTERNAL_ERROR', 'TIMEOUT'];
        console.log("#########################################");
        console.log(`Processing build: ${build.id}`);
        console.log(`Metadata: ${metadata}`);
        console.log("#########################################");
        console.log(JSON.stringify(build));
        console.log("#########################################");

        if (status.indexOf(build.status) === -1) {
            console.log(`Skipping slack notification as ${build.status} is wrong`);
            return;
        }
        if (build.source.repoSource.repoName !== REPO_NAME) {
            console.log(`Skipping slack notification as ${build.source.repoSource.repoName} != ${REPO_NAME}`);
            return;
        }
        // Send message to Slack
        const message = await createSlackMessage(build);
        await webhook.send(message);
    } catch (err) {
        console.error(err);
    }
};

async function get_test_suite_status(build, test_suite) {
    const failure_file = bucket.file(`${build.id}/tests/${test_suite}-failure.txt`);
    try {
        await failure_file.download({destination: `/tmp/${test_suite}-failure.txt`});
        // Yeah. if we can get the file, it means it was a failure :)
        return {
            title: `${test_suite} tests [FAILURE]`,
            title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/tests/${test_suite}.xml.html`,
            color: 'danger'
        }
    } catch (error) {
        console.log(error);
        // Yeah. Error retrieving file indicates that it was success :)
        return {
            title: `${test_suite} tests [SUCCESS]`,
            title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/tests/${test_suite}.xml.html`,
            color: 'good'
        }
    }
}

// createSlackMessage create a message from a build object.
async function createSlackMessage(build) {
    let color = 'warning';
    if (build.status === "SUCCESS") {
        color = 'good'
    } else if (build.status === 'FAILURE' || build.status === 'INTERNAL_ERROR' || build.status === 'TIMEOUT') {
        color = 'danger'
    }
    let attachments = [
        {
            color: color,
            fields: [
                {
                    value: `<https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/index.html| Summary page>`,
                    short: true
                },
                {
                    value: `<https://console.cloud.google.com/cloud-build/builds/${build.id}?project=${build.projectId}| Google Cloud Build>`,
                    short: true
                },
                {
                    value: `<https://console.cloud.google.com/storage/browser/${GCS_BUCKET}/${build.id}/logs/?project=${build.projectId}| Task logs in GCS>`,
                    short: true
                },
                {
                    value: `<https://console.cloud.google.com/logs/viewer?authuser=0&project=${build.projectId}&minLogLevel=0&expandAll=false&resource=build%2Fbuild_id%2F${build.id}| Stackdriver logs>`,
                    short: true
                }
            ]
        },
    ];

    let i;
    for (i = 0; i < test_suites.length; i++) {
        attachments.push(await get_test_suite_status(build, test_suites[i]));
    }

    attachments.push({
        title: 'Documentation',
        title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/docs/index.html`,
        color: 'good'
    });
    let ref = build.source.repoSource.branchName;
    if (ref === undefined) {
        ref = build.source.repoSource.tagName
    }
    if (ref === undefined) {
        ref = build.source.repoSource.commitSha
    }
    return {
        text: `Build in project \`${build.projectId}\` for repo: \`${build.source.repoSource.repoName}\`\nStatus: \`${build.status}\`\nBranch: \`${ref}\`\nBuild id: \`${build.id}\``,
        mrkdwn: true,
        attachments: attachments
    }
}
