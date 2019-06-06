# Prerequisites for Airflow Breeze environment

* If you are on MacOS you need gnu getopt to get the environment running. Typically 
  you need to run `brew install gnu-getopt` and then follow instructions (you need
  to link the gnu getopt version to become first on the PATH). On MacOS you also need
  md5sum, run `brew install md5sha1sum` to install it.

* Google Cloud Platform project which is connected to a billing account that you will use 
  to run the GCP services that Airflow will communicate with. You need to have the
  GCP project id to configure the environment for the first time. 
  
* You should have at least Editor role for the GCP Project and you must have a 
  KMS Encrypter/Decrypter role assigned to your user account. This is needed to
  decrypt and encrypt service account keys shared with your team.

* The `gcloud` and `gsutil` tools installed and authenticated using `gcloud init`. 
  Follow the [Google Cloud SDK installation](https://cloud.google.com/sdk/install) and
  the [Google Cloud Storage Util installation](https://cloud.google.com/storage/docs/gsutil_install).

* The `git` and `python3` installed and available in PATH.

* Python 2.7, 3.5, 3.6 setup - if you want to use local virtualenv / IDE integration. 
  You can install python [Python downloads instructions](https://www.python.org/downloads/)
  Install virtualenv and create virtualenv for all three versions of python. 
  It is recommended to install [Virtualenvwrapper](https://virtualenvwrapper.readthedocs.io/en/latest/)

* Docker Community Edition installed and on the PATH. It should be
  configured to be able to run `docker` commands directly and not only via root user
  - your user should be in `docker` group. See [Docker installation guide](https://docs.docker.com/install/).
  
* You should have forks of the two projects in in your organization or your GitHub user:
  * [Apache Airflow](https://github.com/apache/airflow)
  * [Airflow Breeze](http://github.com/PolideaInternal/airflow-breeze).

* In order to run (via IDE) System Tests with parallel execution (LocalExecutor) 
  you also need to have Postgres server running on your local system and with
  airflow database created. You can install Postgres server via
  [Downloads](https://www.postgresql.org/download/) page. The airflow database can be 
  created using those commands:
  
  ```
  createuser root
  createdb airflow/airflow.db
  ```
