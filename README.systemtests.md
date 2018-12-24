# System Tests

System tests are used to tests Airflow operators with an existing Google Cloud Platform
services. Those are e-2-e tests of the operators.

## Example DAGs

The operators you develop should have example DAGs defined that describe the usage
of the operators, and are used to provide snippets of code for the 
[Documentation of Airflow](https://airflow.readthedocs.io/en/latest/howto/operator.html)

Those example DAGs are also runnable - they are used to system-test the operators 
with real Google Cloud Platform.

After you enter the environment, the interesting example dags are automatically 
symbolically linked to /airflow/dags so that you can start them immediately. 
Those DAGs are immediately available for `airflow` commands - for example 
`airflow list_dags` or `airflow list_tasks <dag_id>`. 

Using symbolic links is for convenience - since those
are symbolic links and the linked DAGS are in your sources which are mounted from
the local host environment - this way you can modify the DAGs locally and they will be
immediately available to run. You can choose which dags you want to link symbolically 
via `AIRFLOW_BREEZE_DAGS_TO_TEST` environment variable in the `variables.env` in 
`airflow-breeze-config` folder in your workspace.

Most of the DAGs you normally work on are in `/workspace/airflow/example_dags` or
`/workspace/airflow/contrib/example_dags/` folder.

It is easiest to run the System Tests from your IDE via specially defined System Test
classes using the standard python Unit Tests. By convention they are placed in 
the `*_system.py` modules of corresponding tests files (in `test/contrib/` directory).
Example of such test is `GcpComputeExampleDagsSystemTest`
in `test/contrib/test_gcp_compute_operator_system.py`.

Such tests in some cases have custom setUp/tearDown routines to set-up the Google
Cloud Platform environment - to setup resources that would be costly to keep running
all the time.

When you run such unit test, the setUp will set everything up - including
authentication using specified service account and creation of necessary resources in
GCP in some cases. For example in case of the `GcpComputeExampleDagsSystemTest` the setUp
creates instances in GCE. After the setup is done the tests run selected example DAG.
DAG id is specified in the constructor of the test. For example in case
of `GcpComputeExampleDagsSystemTest` the test runs `example_gcp_compute.py` example DAG.
After the test is done, the tearDown deletes the resources.

The System Tests can have different configuration in different projects. Configuration for
the tests is stored in `airflow-breeze-config` directory in `variables.env`

The System Tests are skipped by default outside of the container environment (for
example they are skipped in Travis CI). This is controlled by presence of 
service account keys that are used to authenticate with Google Cloud Platform.

## Running System Tests within the container environment

You can run system tests exactly the same way as unit tests (but they are much slower).
The container environment has the environment variables setup in the way that they are
not skipped. Similarly Cloud Build environment is setup in the way to run the tests.

## Running System Tests via IDE (IntelliJ)

You run the system tests via IDE in the same way as in case of the normal unit tests
(see above). The environment variables from last used workspace will be automatically
sources and used by the test. All System Tests require `AIRFLOW__CORE__UNIT_TEST_MODE`
environment variable set to `'True'`. If you do not set the variable, the tests will
warn you to do so.

## Running System Tests via Google Cloud Build (Continuous Integration)

Once can setup Google Cloud Build in the way that all unit and system tests will be run
automatically when you push the code to your GitHub repository. This is described
in [README.setup.md](README.setup.md). 

If you setup your GitHub project with master branch is protected checks enabled
this is an easy way to make sure that you have not broken the existing operators. 
Simply let Cloud Build run all the relevant Unit and System Tests. 
The tests are run in parallel in all configured python
environments - 2.7, 3.5 and 3.6 currently.

When you also setup slack notification, you will get notified about build status
including some useful links such as Documentation, status of tests in each build as
well as link the log files (in Stackdriver for test logs and in Google Cloud Storage
for particular task logs).

TODO: Add screenshots.

## Executing custom setUp/tearDown manually for System Tests

In case such custom setUp / tearDown, there is also a way to run such setUp/tearDown
manually via helper script in the container environment. Typically such helper
script has _helper.py extension - for example `./test_gcp_compute_operator_helper.py`.
You can run such helper with appropriate action (for example:
`./tests/contrib/operators/test_gcp_compute_operator_helper.py --action=create-instance`)
in  order to perform such custom setUp/tearDown. You can run such helper with `--help`
to see the actions available.

This is particularly useful if you want to test each task within DAG separately.

## Long-setup System test cases skipped by default

There are some tests that have very long and non-deterministic setup, those
tests are skipped by default also within container environment and Cloud Build. You can
run such tests automatically by setting appropriate environment variable. For example
`CloudSqlQueryExampleDagsSystemTest` test requires to setup cloud SQL database and it can
take up to 10-15 minutes to complete sometimes. In order to run such tests you need to:

a) Manually run appropriate helper's action to create resources. For example
`./tests/contrib/operators/test_gcp_sql_operator_helper.py --action=create`.
b) set environment variable that disables the test. For example in case of
`CloudSqlQueryExampleDagsSystemTest` you should set GCP_ENABLE_CLOUDSQL_QUERY_TEST
to True. When test is skipped, the reason message will explain how to enable each system
test.
c) Run the test as usual (either via container environment or IDE). For example
`./run_unit_tests.sh tests.contrib.operators.test_gcp_compute_operator_system:CloudSqlQueryExampleDagsSystemTest -s --logging-level=DEBUG`

d) Do not forget to remove the resources after you finished testing. For example
`./tests/contrib/operators/test_gcp_sql_operator_helper.py --action=delete`.

## Testing single tasks of DAGs in container environment

This is the fastest and most developer-friendly way of testing your DAG while you are
developing it. In case special tearDown/setUp is needed you can run it manually before
running the tasks as described in the previous chapter.

You can run separate tasks for each dag via:

`airflow test <DAG_ID> <TASK_ID> <DATE>`

The date has to be in the past and in YYYY-MM-DD form. For example:

`airflow test example_gcp_sql_query example_gcp_sql_task_postgres_tcp_id 2018-10-24`

This runs the test without using/storing anything in the database of airflow and it
produces output in the console rather than log files. You can see list of dags and
tasks via `airflow list_dags` and `airflow list_tasks <DAG_ID>`.

## Run whole example DAGs using full airflow system

-   Use run_environment.sh to run a container with the port forwarded to 8080.
-   (optional), It is easiest run tmux session so that you can have multiple terminals
    within your container.
-   Start the airflow db: `airflow initdb`
-   Start the webserver: `airflow webserver`
-   View the Airflow webapp at `http://localhost:8080/`
-   Start the scheduler in a separate terminal (make sure the separate terminal
    is still in the container; tmux will help here): `airflow scheduler`
-   If not done automatically at entering the container - copy or symbolically link an
    example dag into the DAGs folder:
    `ln -s /workspace/airflow/example_dags/tutorial.py /airflow/dags`
-   It may take up to 5 minutes for the scheduler to notice the new DAG. Restart
    the scheduler manually to speed this up.
