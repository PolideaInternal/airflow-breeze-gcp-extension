# Composer Airflow Breeze Container

It's a breeze to have Airflow running for GCP-related development. It should take 
less than 20 minutes to set you up with latest Airflow source code and be ready to
test and develop your GCP-related operators.

## About

The Composer Airflow Breeze Container allows you to easily create development
environment to work on apache/incubator-airflow repository and test your changes
interfacing with real GCP platform without going through the overhead of manually setting 
up an Airflow environment.

It allows you to have multiple contribution workspaces simultaneously, storing
them in subdirectories of its base directory and you can work on several parallel
project ids in case you have test/staging/development project ids that you use

It also allows you to share common configuration that you use in your project with
your team members - via a shared airflow-breeze-config repository in Google Cloud 
Repositories.

## Intended Usage

-   Build and manage container image that contains all dependencies for Apache Airflow
    to build and run it in one of the three python versions:  2.7, 3.5, 3.6
-   Make updates within the incubator-airflow folder where source of Apache Airflow are 
    checked out (preferably outside of the container - using IDE that is part of the host
    rather than container environment).
-   Test your updates within the container using either standard unit tests or using 
    integration tests with real GCP platform
-   Manage common configuration of the project (per GCP project-id which is shared 
    with your team via airflow-breeze-config repository stored in your project's Google
    Source Repositories)
-   Setup automated builds in Google Cloud Build to be able to verify your builds
    automatically as part of Pull Request in your GitHub project 


## Prerequisites

* You should have a GCP project (with project id) that is connected to a billing
  account that you will use for running the GCP services that Airflow will communicate with.

* You should have `gcloud` and `gsutil` tools installed and you should be authenticated
  using `gcloud init` command before you run the environment.

* You should have `git` and `python3` installed and in your path

* You should have `docker-ce` installed and on your path and your user should be 
  configured to be able to run `docker` commands (usually you should be added to 
  "docker" group) 

## Running environment for the first time (bootstrapping)

When you run the environment for the first time it will automatically check out the
incubator-airflow project from Github fork of the main incubator-airflow project.
The intended workflow is that you make a fork first with either your private account
or your organisation and then you specify that fork the first time you run the project.


`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --repository git@github.com:<ORGANISATION>/incubator-airflow.git` 

or

`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --repository https://github.com/<ORGANISATION>/incubator-airflow.git` 

This will:

* Checkout the incubator-airflow project from your fork and place it in the workspace
  specified. (if you omit workspace, the "default" workspace is used). The project 
  is checked out in <WORKSPACE>/incubator-airflow directory
  
* In case project id is already configured for Airflow Breeze, it will checkout
  configuration to <WORKSPACE>/airflow-breeze-config directory
  
* In case project is not configured yet, it will bootstrap the configuration, ask
  you questions on configuring the project and prepare and push the configuration to the 
  projects 'airflow-breeze-config' repository. It will also add all necessary service
  accounts, configurations, enable all services so that you can start using GCP services
  immediately.
  
* It will build and run docker image for airflow-breeze locally. This image is then used
  to run container in which Airflow environment is setup

* It will cache information about the project and workspace used so that next time
  you do not have to specify it when you run ./run_environment.sh

## Running

To run the container, use run_environment.sh. This will create a workspace with
the name "default".

`./run_environment.sh --project <GCP_PROJECT_ID>`

If you want to use a different workspace, use the --workspace flag:

`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE>`

If you want to forward a port for using the webserver, use the --forward-port flag:

`./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> --forward-port 8080`

By default compute service account is used, you can select different service account
by specifying different key:

`./run_environment.sh --key-name <KEY_NAME>`

You can see the list of available keys via
`./run_environment.sh --key-list`

You can choose a different python environment by `--python` flag (currently you can 
choose 2.7, 3.5 or 3.6 - with 2.7 being default)

For a full list of commands supported, use --help flag:

`./run_environment.sh --help`
 
Those commands allow to manage the image of Airflow Breeze, reconfigure an existing
project.

After you enter the environment, the example dags that are configured in your 
environment (in AIRFLOW_BREEZE_DAGS_TO_TEST environment) are symbolically linked to
/airflow/dags so that you can see them immediately.

### Run an Example Dag manually

-   Use run_environment.sh to run a container with the port forwarded to 8080.
-   (optional), It is easiest run tmux session so that you can have multiple terminals
    within your container.
-   Start the airflow db: `airflow initdb`
-   Start the webserver: `airflow webserver`
-   View the Airflow webapp at `http://localhost:8080/`
-   Start the scheduler in a separate terminal (make sure the separate terminal
    is still in the container; tmux will help here): `airflow scheduler`
-   Copy or symbolically link an example dag into the DAGs folder: `cp
    /wortkspace/airflow/example_dags/tutorial.py
    /airflow/dags`
-   It may take up to 5 minutes for the scheduler to notice the new DAG. Restart
    the scheduler manually to speed this up.

## Run Unit Tests

Ensure that you have set up TravisCI on your fork of the Airflow GitHub repo
before beginning your contribution. This is described in 
https://github.com/apache/incubator-airflow/blob/master/CONTRIBUTING.md#testing-on-travis-ci


After making your changes, use the contribution environment to test them. This can be
done in your IDE using local environment as described below or within the 
environment with runing `--test-target <TEST_PACKAGE>:<TEST_NAME>` for example:

`./run_environment.sh --test-target tests.core:CoreTest`
`./run_environment.sh --test-target tests.contrib.operators.test_dataproc_operator`


### Run Unit tests within a bash session

If you are working within the container, you may use the following commands to
run tests.

`./run_unit_tests.sh tests.core:CoreTest -s --logging-level=DEBUG`
`./run_unit_tests.sh tests.contrib.operators.test_dataproc_operator -s
--logging-level=DEBUG`

### Running particular tasks of DAGs

All the dags are in /airflow/dags folder. You can run separate tasks for each dag
via: 

`airflow test <DAG_ID> <TASK_ID> <DATE>`

The date has to be in the past. For example:

`airflow test example_gcp_sql_query example_gcp_sql_task_postgres_tcp_id 2018-10-24`

This runs the test without using/storing anything in the database of airflow and it 
produces output in the console rather than log files. It's super useful for debugging.

## Run Integration Tests

TODO:

## Working with IDE (IntelliJ)


## Cleanup

If you are done using this tool, remember to delete the image it generated (it
takes up about 2 gigabytes!) Ensure you do not have any open workspaces, then
use `./run_environment.sh --cleanup-image` to delete the image. 

Note that the disk space will not be reclaimed until you run `docker system prune`

You may also delete the workspace folders after you are done with them.

