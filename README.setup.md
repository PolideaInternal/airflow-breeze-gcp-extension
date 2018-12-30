# Setting up Airflow Breeze development environment

This README describes the process of setting up Airflow Breeze Development environment.

# Prerequisites for Airflow Breeze environment

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

* In order to run (via IDE) System Tests which require parallel execution (LocalExecutor) 
  you also need to have Postgres server running on your local system and with
  airflow database created. You can install Postgres server via
  [Downloads](https://www.postgresql.org/download/) page. The airflow database can be 
  created using those commands:
  
  ```
  createuser root
  createdb airflow/airflow.db
  ```

# Bootstrapping the project

The bootstrapping process performs the following:
* [Setting up the workspace](#Setting-up-the-workspace)
* [Checking out the repositories](#Checking-out-the-repositories)
* [Configuring the GCP project](#Configuring-the-GCP-project)
* [Preparing docker image](#Preparing-docker-image)

During the process you should be guided how to perform
[Google Cloud Build setup](#Google-Cloud-Build-setup).

See also [Additional Configuration](#Additional-configuration) for reconfiguring the
project.

## Setting up the workspace

When you run the environment for the first time it will attempt to automatically
create a workspace directory for you in the "workspaces" folder.
The default name of workspace is "default" if you don't specify any. You can
have several different workspaces and switch between them in case you work on several
different GCP projects or several different branches.

Note! We always refer to workspace with it's name which is relative to main 
`airflow-breeze/workspaces` directory. Do not refer to workspace usingfull path.

## Checking out the repositories

When you run the environment for the first time it will attempt to automatically
check out the incubator-airflow project from your Github fork of the
main incubator-airflow project in your workspace. 
The intended workflow is that you make a fork first with either your private account 
or your organisation and then you specify that fork the first time you run the project. 
Reminder - use relative name for the workspace not full path.

```
./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --repository git@github.com:<ORGANIZATION>/incubator-airflow.git
```

Running the environment for the first time performs the following actions:

* Checkout the incubator-airflow project from your fork and place it in the 
  workspace specified (in "workspaces/<WORKSPACE_NAME>" subfolders of the airflow-breeze
  project. If you omit workspace, the "default" workspace is used. The project
  is checked out in `workspaces/<WORKSPACE>/incubator-airflow` directory

* In case project id is already configured for Airflow Breeze by your team, it checks-out
  project's configuration to <WORKSPACE>/airflow-breeze-config directory. More info about
  configuration can be found in the [Configuration variables](#configuration-variables)

* In case project is not configured yet, it bootstraps the configuration, ask
  you questions on configuring the project and prepares and pushes the configuration to
  a new project's `airflow-breeze-config` repository. More about configuring the project
  is described in [Configuring the GCP project](#Configuring-the-GCP-project)

## Configuring the GCP project

The GCP project must be configured before you can use it for system tests. This
process is automated during the bootstrapping. It performs the following tasks:

* ask you to enter/confirm configuration parameters
* enable KMS and Cloud Build for the project
* binds necessary roles to Google Cloud Build
* create keyring and key for encryption
* creates config environment variables 
* encrypt secrets using current KMS key/keyring 
* creates all service accounts
* creates `build` and `test` bucket for the project - see [Buckets](#GCS-buckets) 
* assign all required roles to all service accounts
* apply all permissions to buckets created for service accounts that need it
* copy initial files to the buckets
* configure authentication for Cloud Source Repository
* bootstraps configuration repository and HelloWorld repository (for Cloud Functions)
* Pushes the repositories to the Cloud Source Repositories (must be reviewed and confirmed)

## Preparing docker image

The bootstrap process builds docker image for `airflow-breeze`. 
This image is used to run container in which Airflow environment is setup. 
If the image has not yet been created, by default it is build it locally.

Tje `airflow-breeze` image is rebuilt every time sources change and you enter the 
environment. You might skip this step by providing
`--do-not-rebuild-image` flag when you run `run-environment.sh`.

Instead of building the image locally you can choose to download the image from your 
project's registry via providing `--download-image` flag. However this is only possible
if your team set-up Cloud Build as described in [Google Cloud Build Setup](#Google-Cloud-Build-setup).
In such cae the image is automatically built and stored in your project's repository
every time `airflow-breeze` is pushed to your Github fork. The `--download-image` flag
automatically disables local rebuilding.

# Google Cloud Build setup

## Setting up Google Cloud Build (Continuous Integration)

Airflow Breeze integrates with Google Cloud Build allowing you to automate your
development workflow.

The setup process guides you how to do it but in summary this is is as 
easy as connecting [Google Cloud Build application](https://github.com/marketplace/google-cloud-build)
to your forks of [airflow-breeze](http://github.com/PolideaInternal/airflow-breeze) and
[incubator-airflow](https://github.com/apache/incubator-airflow) GitHub projects.

The first project sets up automated build of your own airflow-breeze image (stores it in
Google Container Registry) and the second is using this image to perform actual test
execution - of the tests that you specify that should be run within the environment.
You can also read more about building GitHub apps in Google Cloud Build in 
[Run builds on GitHub](https://cloud.google.com/cloud-build/docs/run-builds-on-github)

## Setting up Google Cloud Build notifications

In order to see results from Google Cloud Build, you should setup automated 
notification of build results (currently you can setup notifications via incoming slack
webhook). This requires setting up `airflow-breeze-config` Google Cloud Build trigger to 
deploy Google Cloud Function. You can see the triggers configured at 
the [Triggers page](https://console.cloud.google.com/cloud-build/triggers)

These are example Slack notifications that inform you about build status:

TODO: Add screenshot

You can follow the links and you have the Summary Page which is publicly available and
you can share it with others.

You can also modify the code of slack notification function and deploy it manually.
The code is in your workspace's `airflow-breeze-config/notifications/slack`. In order
to modify the code, you should run `./deploy_function.bash` first - the function will
be deployed and the code to the function will be symbolically linked in the 
`airflow-breeze-config/notifications/slack` directory from the main
airflow-breeze/notifications/slack directory. You can iterate locally by modifying 
these sources and running `./deploy-function.bash` but in order to make the change 
permanent you have to commit it to your fork of `airflow-breeze`.

# Additional configuration

After the project is bootstrapped you can reconfigure the existing project as well
as setup Travis CI for running all unit tests automatically.

## Reconfiguring the GCP project

If you want to make sure your project has latest setup, you can always reconfigure it 
by running `./run_environment.sh --reconfigure-gcp-project`.

It will performs the following tasks:
* ask you to confirm configuration parameters
* re-enable KMS and Cloud Build for the project
* re-binds necessary roles to Google Cloud Build
* re-create keyring and key for encryption if they are missing
* apply bootstrap template to the existing environment variables
    * adds new variables from bootstrap
    * removes variables not existing in bootstrap
* re-encrypt secrets using current KMS key/keyring 
* creates missing service accounts
* create `build` and `test` bucket for the project if missing 
* re-assign all required roles to all service accounts
* re-apply all permissions to buckets created for service accounts that need it
* restore initial files in the buckets (without deleting other files)
* re-enable authentication for Cloud Source Repository
* Pushes changes to the Cloud Source Repositories (must be reviewed and confirmed)

## Recreating the GCP project

Sometimes it is useful to 

If you want to recreate your project from the scratch, you can always recreate it 
by running `./run_environment.sh --recreate-gcp-project`. It will 
perform the same tasks as reconfiguring the project plus:

* re-create encryption keys
* delete and re-create all service accounts
* delete and re-create the buckets (that includes deleting build log history)

You  can use it at any time when you want to make sure that some previously
used credentials are not misused as it will use completely new set of credentials
for the project. In case project is recreated, all team members will have to pull 
the pushed version of `airflow-breeze-config` in order to be able to authenticate with 
service accounts of the project.

## Setting up Travis CI for unit tests

You should also setup Travis CI for running all unit tests automatically as described in
[CONTRIBUTING.md](https://github.com/apache/incubator-airflow/blob/master/CONTRIBUTING.md#testing-on-travis-ci)

# Appendixes

## Reinstalling latest airflow dependencies

When you already have a local `airflow-breeze` image built, the dependencies of
incubator-airflow are installed at the time of the installation. Even if they
change later and new dependencies will be added, this does not cause the dependencies
to be re-installed - they are only added incrementally when you enter the container
environment. The more dependencies are added, the longer it will take to enter the
environment. Therefore from time to time you should force reinstalling the dependencies.
This can be done by increasing value of REBUILD_AIRFLOW_BREEZE_VERSION in 
the [Dockerfile](Dockerfile). Once you commit it and other team member synchronize it,
next time when they enter the environment, all python environments will rebuild with
latest dependencies.

## Configuration variables

This chapter explains what is inside `airflow-breeze-config` folder. The folder 
is placed in your workspace is used to share configuration 
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
  Google Cloud Build. Note that source code for notification functions are
  stored in the (notifications)[notifications] folder. You can use 
  provided bash `deploy_function.bash` scripts to have symbolic links automatically 
  added for your config where you can develop and deploy functions locally - but
  ultimately you need to commit the code from the (notifications)[notifications] folder
  so that the functions are automatically deployed (via cloud function trigger). 
* decrypted_variables.env - some of the variables in variables.env are encrypted,
  when you enter the environment they are automatically decrypted and stored in this
  file (and sourced so that they are available in the container environment). This 
  file is git-ignored so that it won't be accidentally checked in to the repository.

Note that you should commit and push/pull changes to the `airflow-breeze-config` 
additionally to changes in the main `incubator-airflow` project. This way you can share
new/changed configuration with your team. Note that there are also configuration
templates in `bootstrap` folder (prefixed with `TEMPLATE-`) and whenever you enter
the container, the `./run_environment.sh` script verifies automatically if you have 
any changes in your config that were not added to the bootstrap template (and the
other way round). This helps in keeping bootstrap template and your configuration
in sync.

## GCS Buckets

This chapter explains what buckets are created in Google Cloud Storage for the 
test environment.

There are two buckets created for the GCP projects. By default they have names
following your project id (`<PROJECT_ID>-builds`, `<PROJECT_ID>-tests`). You can 
change the default prefixes however during bootstrapping process.

The `builds` bucket stores all build artifacts, it's permissions are set as
read for everyone, which means that you can share the links to files stored
there with anyone.

The `tests` bucket is used to perform GCS related tests.
