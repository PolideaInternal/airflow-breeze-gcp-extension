# Setting up Airflow Breeze development environment

## Prerequisites for Airflow Breeze environment

* Google Cloud Platform project which is connected to a billing account that you will use 
  to run the GCP services that Airflow will communicate with. You need to have the
  GCP project id to configure the environment for the first time. You should have at 
  least Editor role for the GCP Project.

* The `gcloud` and `gsutil` tools installed and authenticated using `gcloud init`. 
  Follow the [Google Cloud SDK installation](https://cloud.google.com/sdk/install) and
  the [Google Cloud Storage Util installation](https://cloud.google.com/storage/docs/gsutil_install).

* The `git` and `python3` installed and available in PATH.

* The `iconv` tool should be installed and available in PATH.

* Python 2.7, 3.5, 3.6 - if you want to use local virtualenv / IDE integration. 
  You can install python [Python downloads instructions](https://www.python.org/downloads/)
  Install virtualenv and create virtualenv for all three versions of python. 
  It is recommended to install [Virtualenvwrapper](https://virtualenvwrapper.readthedocs.io/en/latest/)

* Docker Community Edition installed and on the PATH. It should be
  configured to be able to run `docker` commands directly and not only via root user
  - your user should be in `docker` group. See [Docker installation guide](https://docs.docker.com/install/).
  
* You should have forks of the two projects in in your organization or your GitHub user:
  * [Apache Incubator Airflow](https://github.com/apache/incubator-airflow)
  * [Airflow Breeze](http://github.com/PolideaInternal/airflow-breeze).

## Bootstrapping environment - running it for the first time

When you run the environment for the first time it will attempt to automatically
check out the incubator-airflow project from your Github fork of the
main incubator-airflow project. The intended workflow is that you make a fork first
with either your private account or your organisation and then you specify that
fork the first time you run the project. Note! <WORKSPACE> is name of directory (relative)
that will become a workspace directory inside Airflow Breeze folder.

`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --repository git@github.com:<ORGANIZATION>/incubator-airflow.git`

or

`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --repository https://github.com/<ORGANIZATION>/incubator-airflow.git`

Running the environment for the first time performs the following actions:

* Checkout the incubator-airflow project from your fork and place it in the workspace
  specified. (if you omit workspace, the "default" workspace is used). The project
  is checked out in <WORKSPACE>/incubator-airflow directory

* In case project id is already configured for Airflow Breeze by your team, it checks-out
  configuration to <WORKSPACE>/airflow-breeze-config directory

* In case project is not configured yet, it bootstraps the configuration, ask
  you questions on configuring the project and prepares and pushes the configuration to
  a new project's 'airflow-breeze-config' repository. It also creates all necessary
  service accounts, configurations, enables all services so that you can start
  developing GCP operators immediately.

* It downloads docker image for airflow-breeze from your shared per-project
  Google Container Registry. This image is used to run container in which Airflow
  environment is setup. If the image has not yet been created and stored in the registry,
  it will build it locally. You can also force building the image locally
  by adding `-r` flag. If you setup Google Cloud Build triggers, the image is built
  every time airflow breeze is pushed to its Github fork' repository.

## Configuration -  airflow-breeze-config

The `airflow-breeze-config` folder in your workspace is used to share configuration 
of your project between your team members. You should pull the configuration directory 
periodically and push your changes in order to exchange configuration with your 
team members.

The `airflow-breeze-config` directory contains environment variables in variables.env 
file. This .env file is sourced when you enter the environment, 
when you run System Tests via IDE or when you run System Tests in Google Cloud Build.

Additionally the `airflow-breeze-config` directory contains:

* keys directory - where service account keys (encrypted) are kept in the repository
  and where they are decrypted locally
* notifications directory - where notifications configured per project are kept. The
  notifications are implemented as Google Cloud Functions that are triggered by
  Google Cloud Build
* decrypted_variables.env - some of the variables in variables.env are encrypted,
  when you enter the environment they are automatically decrypted and stored in this
  file (and sourced so that they are available in the container environment). This 
  file is git-ignored so that it won't be accidentally checked in to the repository.
  
## Setting up Google Cloud Build (Continuous Integration)

Airflow Breeze integrates with Google Cloud Build allowing you to 

The setup process guides you how to do it, but in summary this is is as 
easy as connecting [Google Cloud Build application](https://github.com/marketplace/google-cloud-build)
to your forks of [airflow-breeze](http://github.com/PolideaInternal/airflow-breeze) and
[incubator-airflow](https://github.com/apache/incubator-airflow)  GitHub projects.
The first project sets up automated build of your own airflow-breeze image (stores it in
Google Container Registry) and the second is using this image to perform actual test
execution - of the tests that you specify that should be run within the environment.

You can also setup automated notification of build results. This is as easy as setting 
up `airflow-breeze-config` Google Cloud Build trigger to deploy Google Cloud Function.
You can see the triggers configured at the [Triggers page](https://console.cloud.google.com/cloud-build/triggers)
This enables Slack notifications that inform you about build status:

TODO: Add screenshot

## Setting up Travis CI for unit tests

You should also setup Travis CI for running all unit tests automatically as described in
[CONTRIBUTING.md](https://github.com/apache/incubator-airflow/blob/master/CONTRIBUTING.md#testing-on-travis-ci)
