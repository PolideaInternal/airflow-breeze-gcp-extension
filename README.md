<p align="center">
  <img src="images/AirflowBreeze_logo.png" alt="Airflow Breeze Logo"/>
</p>

With Airflow Breeze It's a breeze to start developing Airflow operators for Google Cloud 
Platform operators. It should take lass than 30 minutes to have you set you up with an
environment where you are ready to develop your code and test it against a real
Google Cloud Platform services.

# About Airflow Breeze

The Airflow Breeze Container allows you to easily create Docker development
environment to work on apache/airflow repository and test your changes
interfacing with a Google Cloud Platform without going through the overhead of 
manually setting up an Airflow environment, Google Cloud Platform project and 
configuring service accounts to access the platform in secure way - all done in
the way that can be shared with your team so that you can work together on a project.

It allows you to have multiple contribution workspaces simultaneously, storing
them in subdirectories of its base directory and you can work on several parallel
project ids in case you have test/staging/development project ids that you use.

The workspaces are stored in `workspace` subdirectory of your project. It will
be automatically created when you first time enter the container environment.

It also allows you to share common configuration that you use in your project with
your team members - via a shared airflow-breeze-config repository in Google Cloud
Repositories.

Last but not least - the environment provides comfortable IDE integration - you
can easily use your favourite IDE (for example PyCharm/IntelliJ) to run Unit
Tests and System Tests interacting with Google Cloud Platform - source code is 
shared between the container environment and your local IDE so it's easy to 
develop and test your code locally but also system test it in the container.

You can read more about architecture of the environment in
[Design of the Airflow Breeze environment](https://docs.google.com/document/d/15hdqL4bWU0646nAvxsEjIEr0gHOhMu6OByDWI1oiE7w/edit#heading=h.rcqupn6ux98a)


# Intended Usage

-   Build and manage container image that contains all dependencies for Apache Airflow
    to build and run it in one of the three python versions:  2.7, 3.5, 3.6
-   Develop source code within the `airflow` folder where source of Apache Airflow
    are checked out (preferably outside of the container - using IDE that is part of 
    the host rather than container environment).
-   Test your code easily within the container using Unit Tests or 
    System Tests interacting with Google Cloud Platform.
-   Manage common configuration of the project (per GCP project-id) which is shared
    with your team via airflow-breeze-config repository - stored in your project's Google
    Source Repositories and locally checked out in `<WORKSPACE>/config` directory.
-   Setup automated builds in Google Cloud Build to verify your builds
    automatically and run all relevant unit and System Tests as part of Pull Request 
    process of your GitHub project

# Setting up Google Cloud Project with Airflow Breeze

Bootstrapping the Google Cloud Platform project, first time setup of your workspace
and configuration is described in [README.setup.md](README.setup.md). You 
can skip this part entirely if the Google Cloud Platform project is already setup
for Airflow Breeze and you setup local development environment with already
existing project id.

# Creating local development environment

You need to fulfill prerequisites described in 
[README.prerequisites.md](README.prerequisites.md) in order to proceed.

To run the container, use `./run_environment.sh.`. You need to do it at least
once to have everything setup for you IDE integration and in order to be able
to run [Unit tests](README.unittests.md) or [System tests](README.systemtests.md)
using your IDE.

The first time you enter the environment you will have to specify project and
workspace. Optionally you can specify
Python version (2.7, 3.5 or 3.6).

```
./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE> [ --python <PYTHON_VERSION>]
```

You will get information that you enter the environment without the GCP 
service account key - that's OK and you are OK to proceed at this stage. You can always 
choose or change the key later.

When you enter the environment, it caches information about the project,
workspace, key and python versions used so that next time you do not have to 
specify it when you run `./run_environment.sh`. 

You can always override those cached values with using appropriate flags 
(see [Entering the container](#entering-the-container) chapter on how to do it.

When you enter the environment, your source files are mounted inside the docker
container (in `/workspace` folder) and changes to the sources done in host
are synchronized in real time with container sources. 
This is a very convenient development environment as you can use your local IDE 
to work on the code and you can keep the environment running all the time 
and not worry about copying the files.

AIRFLOW_HOME is set to `/airflow` - and you will find all the logs, dag folder, 
unit test databases etc. there.

# Entering the container

## Changing the service account key without leaving the environment

Once in the environment, you can always change the service account key used by
running `set_gcp_key <KEY_NAME>`. This will also reset the Postgres database
and re-link all symbolic links to example DAGs as explained in 
[README.systemtests.md](README.systemtests.md#Example-DAGs)

## Resetting the database

Every time you enter the environment, the database is created from scratch. You can
force-reset the database without leaving the environment with above mentioned
`set_gcp_key <KEY_NAME>` command. The key should be provided before after
resetting the database it must be created as connection in the database.

## Running the container with last used configuration

Last used workspace, project, key and python version are used in this case:

```
./run_environment.sh
```

## Forwarding webserver port to Airflow's UI

If you want to forward a port for using the webserver, use the --forward-webserver-port flag:

```
./run_environment.sh --forward-webserver-port 8080
```

Note that you need to start the webserver manually with `airflow webserver` command.

## Forwarding Postgres port to Airflow's Postgres DB

If you want to forward a port for remotely accessing the database, use the --forward-postgres-port flag:

```
./run_environment.sh --forward-postgres-port 5433
```

Use localhost host, chosen port, `root` user, `airflow` password and 
`airflow/airflow.db` database to connect.

Example JDBC connection: `jdbc:postgresql://127.0.0.1:5433/airflow/airflow.db`
 

## Creating new workspace / changing workspace

If you want to use a different workspace, use the --workspace flag. This will
automatically create the workspace if the workspace does not exist.

```
./run_environment.sh --project <GCP_PROJECT_ID> --workspace <WORKSPACE>
```

## Choosing different service account key

You can select different service account by specifying different key:

```
./run_environment.sh --key-name <KEY_NAME>
```

You can see the list of available keys via
```
./run_environment.sh --key-list
```

It's a deliberate decision to use separate service accounts for each
service - this way the service accounts have minimal set of permissions required
to run particular operators. This allows to test if there are special
permissions needed to access particular service or run the operator.

## Choosing different python environment

You can choose a different python environment by `--python` flag (currently you can
choose 2.7, 3.5 or 3.6 - with 3.6 being default)

## Changing project

You can change project in already created workspace. You will be asked for confirmation
as this is a destructive operation - local `config` in the workspace
will be deleted and replaced with new project's specific configuration.

```
./run_environment.sh --project <GCP_PROJECT_ID>
```

## Adding new service accounts

When you want to add a new service account to your project you need to reconfigure the
project. You need to add your service account with required roles in
[_bootstrap_airflow_breeze_config.py](bootstrap/_bootstrap_airflow_breeze_config.py)
and run `./run_environment.sh --reconfigure-gcp-project`. 
See [Reconfiguring the project](README.setup.md#Reconfiguring-the-GCP-project) for details.

This will re-enable all services, will create missing service accounts, reassigns
roles to the project and reapply all permissions.

## Reconfiguring or recreating the project

You can read about reconfiguring and recreating the project in 
[README.setup.md](README.setup.md#Additional-configuration)

## Custom docker flags

You can add custom docker flags to `./run_environment.sh` by adding the docker flags after
`--`. For example:

```
./run_environment.sh -- -v /home:/mapped-home
```


## Other operations

For a full list of commands supported, use --help flag:

```
./run_environment.sh --help
```

Those commands allow to manage the image of Airflow Breeze, reconfigure an existing
project, reconfigure the project, recreate the GCP project with all sensitive data,
initialize local virtualenv for IDE integration and manage the airflow breeze docker
image.

# Testing

There are two ways of testing Airflow Breeze. Unit Tests can be run standalone and 
do not communicate with Google Cloud Platform, where System Tests can be used
to run tests against an existing Google Cloud Platform services. Both unit 
and system tests can be run via local IDE (for example IntelliJ or PyCharm) and 
via command line using the `airflow-breeze` container.

You can read more about it:

* Running Unit Tests in [README.unittests.md](README.unittests.md)
* Running System Tests in [README.systemtests.md](README.systemtests.md)

# Cleanup

If you are done using container, you might want to delete the image it generated or
downloaded (it takes up about 2 gigabytes!) Ensure you do not have any open workspaces,
then use `./run_environment.sh --cleanup-image` to delete the image.

Note that after cleanup the disk space is not reclaimed. It will be reclaimed when you run
`docker system prune`.

You may also delete the workspace folders after you are done with them.

# Appendix: current ./run_environment flags

```
Usage run_environment.sh [FLAGS] [-t <TEST_TARGET> | -x <COMMAND> ]

Flags:

-h, --help
        Shows this help message.

-p, --project <GCP_PROJECT_ID>
        Your GCP Project Id (required for the first time). Cached between runs.

-w, --workspace <WORKSPACE>
        Workspace name [default]. Folder with this name is created and sources
        are downloaded automatically if it does not exist. Cached between runs. [default]

-k, --key-name <KEY_NAME>
        Name of the GCP service account key to use by default. Keys are stored in
        '<WORKSPACE>/config/key' folder. Cached between runs. If not
        specified, you need to confirm that you want to enter the environment without
        the key. You can also switch keys manually after entering the environment
        via 'gcloud auth activate-service-account /root/config/keys/<KEY>'.

-K, --key-list
        List all service keys that can be used with --key-name flag.

-P, --python <PYTHON_VERSION>
        Python virtualenv used by default. One of ('2.7', '3.5', '3.6'). [2.7]

-f, --forward-webserver-port <PORT_NUMBER>
        Optional - forward the port PORT_NUMBER to airflow's webserver (you must start
        the server with 'airflow webserver' command manually).

-F, --forward-postgres-port <PORT_NUMBER>
        Optional - forward the port PORT_NUMBER to airflow's Postgres database. You can
        login to the database as the user root with password airflow. Database of airflow
        is named airflow/airflow.db.

Reconfiguring existing project:

-g, --reconfigure-gcp-project
        Reconfigures the project already present in the workspace.
        It adds all new variables in case they were added, creates new service accounts
        and updates to latest version of the used notification cloud functions.

-G, --recreate-gcp-project
        Recreates the project already present in the workspace. DELETES AND RECREATES
        all sensitive resources. DELETES AND RECREATES buckets with result of builds
        DELETES AND RECREATES service account keys, DELETES AND GENERATES encrypted
        passwords. Then it performs all actions as in reconfigure project.

-z, --compare-bootstrap-config
        Compares bootstrap configuration with current workspace configuration. It will
        report differences found and suggestions how those two should be aligned.

Initializing your local virtualenv:

-e, --initialize-local-virtualenv
        Initializes locally created virtualenv installing all dependencies of Airflow.
        This local virtualenv can be used to aid autocompletion and IDE support as
        well as run unit tests directly from the IDE. You need to have virtualenv
        activated before running this command.

Managing the docker image of airflow-breeze:

-i, --do-not-rebuild-image
        Don't rebuild the airflow docker image locally

-u, --upload-image
        After rebuilding, also upload the image to GCR repository
        (gcr.io/<GCP_PROJECT_ID>/airflow-breeze). Needs GCP_PROJECT_ID.

-d, --download-image
        Downloads the image from GCR repository (gcr.io/<GCP_PROJECT_ID>/airflow-breeze)
        rather than build it locally. Needs GCP_PROJECT_ID.

-c, --cleanup-image
        Clean your local copy of the airflow docker image.
        Needs GCP_PROJECT_ID.


Automated checkout of airflow project:

-R, --repository [REPOSITORY]
        Repository to clone in case the workspace is not checked out yet
        [].
-B, --branch [BRANCH]
        Branch to check out when cloning the repository specified by -R. [master]

-S, --synchronise-master
        Synchronizes master of your local and origin remote with the main Apache repository.

Optional unit tests execution (mutually exclusive with running arbitrary command):

-t, --test-target <TARGET>
        Run the specified unit test target. There might be multiple
        targets specified.



Optional arbitrary command execution (mutually exclusive with running tests):

-x, --execute <COMMAND>
        Run the specified command. It is run via 'bash -c' so if you want to run command
        with parameters they must be all passed as one COMMAND (enclosed with ' or ".
```
