const {Storage} = require('@google-cloud/storage');
const {PubSub} = require('@google-cloud/pubsub');
const Octokit = require('@octokit/rest');

let ps;

const IncomingWebhook = require('@slack/client').IncomingWebhook;

const GCS_BUCKET = process.env.GCS_BUCKET;
const AIRFLOW_REPO_NAME = process.env.AIRFLOW_REPO_NAME;
const PROJECT_ID = process.env.PROJECT_ID;
const AIRFLOW_BREEZE_GITHUB_ORGANIZATION = process.env.AIRFLOW_BREEZE_GITHUB_ORGANIZATION;

const webhook = new IncomingWebhook(process.env.SLACK_HOOK);
const test_suites = process.env.AIRFLOW_BREEZE_TEST_SUITES.split(" ");

const storage = new Storage({
    projectId: PROJECT_ID,
});

const bucket = storage.bucket(GCS_BUCKET);
const octokit = new Octokit();

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
        const build_resource_content = JSON.stringify(build);
        const build_resource_file = bucket.file(`${build.id}/build_resource.json`);
        await build_resource_file.save(build_resource_content);
        console.log(`The build resource is saved at https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/build_resource.json`);
        console.log("#########################################");

        if (status.indexOf(build.status) === -1) {
            console.log(`Skipping slack notification of not interesting ${build.status} state. Interesting states: ${status}`);
            return;
        }
        if (build.substitutions === undefined || build.substitutions.REPO_NAME === undefined ||
            build.substitutions.REPO_NAME !==  AIRFLOW_REPO_NAME) {
            console.log(`Skipping slack notification on substitutions = ${JSON.stringify(build.substitutions)}`);
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
    const success_file = bucket.file(`${build.id}/tests/${test_suite}-success.txt`);
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
        try {
            await success_file.download({destination: `/tmp/${test_suite}-success.txt`});
            return {
                title: `${test_suite} tests [SUCCESS]`,
                title_link: `https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/tests/${test_suite}.xml.html`,
                color: 'good'
            }
        } catch (error) {
            console.log(error);
            console.log(`Neither success nor failure file found. The test suite ${test_suite} was not run. Skipping it`);
            return undefined;
        }
    }
}

async function get_documentation_attachment(build, attachments) {
    const documentation_index_file = bucket.file(`${build.id}/docs/index.html`);
    try {
        await documentation_index_file.download({destination: `/tmp/index.html`});
        attachments[0].fields.push({
            value: `<https://storage.googleapis.com/${GCS_BUCKET}/${build.id}/docs/index.html| Documentation>`,
            short: true
        });
    } catch (error) {
        console.log(error);
        console.log("Documentation index is missing. Skipping documentation attachment.");
    }
}

// createSlackMessage create a message from a build object.
async function createSlackMessage(build) {
    let color = 'warning';
    let repo_name = build.substitutions.REPO_NAME;
    let branch_name = build.substitutions.BRANCH_NAME;
    let tag_name = build.substitutions.TAG_NAME;
    let commit_sha = build.substitutions.COMMIT_SHA;
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
                    value: `<https://console.cloud.google.com/cloud-build/builds/${build.id}?project=${build.projectId}| Google Cloud Build console>`,
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
    await get_documentation_attachment(build, attachments);

    const commit_info = await octokit.repos.getCommit({owner: AIRFLOW_BREEZE_GITHUB_ORGANIZATION, repo: repo_name, sha: commit_sha});
    const data = commit_info.data;
    console.log(data);
    attachments[0].fields.push({
        value: `Branch: <https://github.com/${AIRFLOW_BREEZE_GITHUB_ORGANIZATION}/${repo_name}/tree/${branch_name}| ${branch_name}>`,
        short: true
    });
    attachments[0].fields.push({
        value: `Commit: <https://github.com/${AIRFLOW_BREEZE_GITHUB_ORGANIZATION}/${repo_name}/commit/${commit_sha}| ${data.commit.message.split('\n')[0]}>`,
    });

    let i;
    for (i = 0; i < test_suites.length; i++) {
        let attachment_test_suite = await get_test_suite_status(build, test_suites[i]);
        if (attachment_test_suite !== undefined) {
            attachments.push(attachment_test_suite);
        }
    }

    return {
        text:
            `Build in project \`${build.projectId}\` for repo: \`${repo_name}\`
 Status: \`${build.status}\`
 Branch: \`${branch_name}\`
 Tag: \`${tag_name}\`
 Commit SHA: \`${commit_sha}\`
 Commit message: \`${data.commit.message.split('\n')[0]}\`
 Committer: \`${data.commit.committer.name}\`
 Author: \`${data.commit.author.name}\`
 Build id: \`${build.id}\``,
        mrkdwn: true,
        attachments: attachments
    }
}
