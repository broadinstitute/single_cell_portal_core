# SINGLE CELL PORTAL README

[![codecov](https://codecov.io/gh/broadinstitute/single_cell_portal_core/branch/development/graph/badge.svg?token=HMWE5BO2a4)](https://codecov.io/gh/broadinstitute/single_cell_portal_core)
![Build Status](https://github.com/broadinstitute/single_cell_portal_core/actions/workflows/run-all-tests.yml/badge.svg)
## SETUP

This application is built and deployed using [Docker](https://www.docker.com), specifically native
[Docker for Mac OSX](https://docs.docker.com/docker-for-mac/). Please refer to their online documentation for instructions
on installing Docker.

## PULLING/BUILDING THE DOCKER IMAGE

To pull the Docker image that Single Cell Portal is built off of, run the following command:
```
docker pull gcr.io/broad-singlecellportal-staging/single-cell-portal:development
```

This is not strictly necessary as a pre-flight step, but will make calling `bin/boot_docker` faster 
(see [Running the Container](#running-the-container)) for more information.

To build the Docker image locally, run the following command from the project root directory:
```
docker build -t gcr.io/broad-singlecellportal-staging/single-cell-portal:development .
```

This will start the automated process of building the Docker image for running the portal.  The image is based on the
[Passenger-docker baseimage](https://github.com/phusion/passenger-docker) and comes with Ruby, Nginx, and Passenger by
default, but built on a different base image and with additional packages added to the [Broad Institute SCP Rails baseimage](https://github.com/broadinstitute/scp-rails-baseimage/)
which pulls from the original baseimage. The extended image contains other required libraries, and self-signed SSL 
certificates & CA Authority for doing local development in https.

*If this is your first time building the image, it may take several minutes to download and install everything.*

## BEFORE RUNNING THE CONTAINER

This project uses [MongoDB](https://hub.docker.com/_/mongo/) as the primary datastore, and connects to a remote MongoDB
instance in all environments. In order for the portal to operate correctly, you will need to provision
a MongoDB instance in Google Cloud Platform.  This can be done using [Google Click to Deploy](https://console.cloud.google.com/marketplace/details/click-to-deploy-images/mongodb),
or via providers such as [MongoDB Atlas](https://www.mongodb.com/cloud/atlas).  You may also provision a database manually
using a VM in Google Compute Environment if you so desire.

The only requirement is that you add a user account called "single_cell" to your Single Cell Portal database in whatever
instances you create.

## EXTERNAL DEPENDENCIES AND INTEGRATIONS

The Single Cell Portal has several external dependencies & integrations that are either required for operation, or enable
extra security/reporting features when certain variables are set.  If you are deploying your own instance of the Single Cell Portal,
you will need to create resources and accounts in order for the portal to function.  They are as follows:

#### [Google Cloud Platform](https://console.cloud.google.com) (REQUIRED)

The Single Cell Portal is currently deployed in Google Cloud Platform (specifically, on a Google Compute Engine virtual machine).
This is a requirement for all functionality.  The portal utilizes GCP service accounts for making authenticated calls to
various APIs as a part of normal usage.  For more information on how to configure your GCP project, please see
[Local Development or Deploying a Private Instance](#local-development-or-deploying-a-private-instance) below.

#### [Terra](https://terra.bio/) (REQUIRED)

The Single Cell Portal uses Terra, which is the Broad Institute's cloud-based analysis platform.  The portal uses
Terra both as a data and permission store, as well as an analysis platform.  For more information on the integration
itself, see [Terra Integration](#terra-integration) below, or for setting up your own Terra project, see
[Local Development or Deploying a Private Instance](#local-development-or-deploying-a-private-instance) below.

#### [Sentry](https://sentry.io)

The Single Cell Portal is set up to integrate with Sentry, an external error reporting service.  This is not required for
the portal to function (this feature is opt-in and only functions when certain parameters are set at runtime).  Developers
deploying their own instance will need to register for an account with Sentry, and then set the <code>SENTRY_DSN</code>
environment variable when deploying your instance (see [Running the Container](#running-the-container) and
[DOCKER RUN COMMAND ENVIRONMENT VARIABLES](#docker-run-command-environment-variables) for more detail).

Note - while the Sentry DSN is stored with secrets and may appear as one, it is not a secret and Sentry's 
official stance is that [the Sentry DSN does not need to be kept private](https://github.com/getsentry/sentry-docs/pull/3123/files). 

#### [TCell Web Application Firewall](https://tcell.io)

The Single Cell Portal employs the TCell web application firewall as part of its security configuration.  This is not
required for the portal to function (this feature is opt-in and only functions when certain parameters are set at runtime).
Developers deploying their own instance will need to register for an account with TCell, and then set the <code>TCELL_AGENT_APP_ID</code>,
<code>TCELL_AGENT_API_KEY</code> and <code>T_CELL_SERVER_AGENT_API_KEY</code>environment variables when deploying your 
instance (see [Running the Container](#running-the-container) and [DOCKER RUN COMMAND ENVIRONMENT VARIABLES](#docker-run-command-environment-variables) 
for more detail).

#### [Google Analytics](https://analytics.google.com)

The Single Cell Portal is configured to report web traffic to Google Analytics.  You will first need to set up an account
on Google Analytics, and then to enable simply set the <code>GA_TRACKING_ID</code> environment variable when deploying
(see [Running the Container](#running-the-container) and [DOCKER RUN COMMAND ENVIRONMENT VARIABLES](#docker-run-command-environment-variables)
for more detail).

## LOCAL DEVELOPMENT OR DEPLOYING A PRIVATE INSTANCE

If you are not part of the Single Cell Portal development team and are trying to use the portal locally or deploying a
private instance of the Single Cell Portal (i.e. not any Broad Institute instance), there are a few extra steps that need
to be taken before the portal is configured and ready to use:

* **Create a GCP project**: Even if you are deploying locally or in a private cluster, the portal requires a Google Cloud
Plaform project in order to handle OAuth callbacks and service account credentials.  To create your project:
  * Visit https://console.developers.google.com
  * Click 'Select a project' in the top lefthand corner and click the + button
  * Name your new project and save

* **OAuth Credentials**: Once your project is created, you will need to create an OAuth Client ID in order to allow users
to log in with their Google accounts.  To do so:
  * Log into your new GCP project
  * Click the navigation menu in the top left and select 'APIs & Services' > 'Credentials'
  * Click 'Create Credentials' > 'OAuth Client ID'
  * Select 'Web Application', and provide a name
  * For 'Authorized Javascript Origins', enter the following:
    * `https://(your hostname)`
  * For 'Authorized redirect URIs', enter the following:
    * `https://(your hostname)/single_cell/users/auth/google_oauth2/callback`
    * `https://(your hostname)/single_cell/api/v1/oauth2_redirect`
  * Save the client id
  * You will also want to create a second OAuth Client ID to use in local development, using `localhost` as the hostname

* **Authorizing your OAuth Audience**
  * Once you have exported your OAuth credentials, you will need to have your client id authorized to allow it to make
  authenticated requests into the Terra API as per [OpenID Connect 1.0](http://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
    *  Send an email to **dsp-devops@broadinstitute.org** with your OAuth2 client ID(s) so it can be added to the authorized list

* **GCP Service Account keys**: Regardless of where the portal is deployed, it requires a Google Cloud Platform Service
Account in order to make authenticated calls into Terra and Google Cloud Storage.  Therefore, you must export the
default service account key.  See https://developers.google.com/identity/protocols/OAuth2ServiceAccount for more information
about service accounts.  To export the credentials:
	*  Log into your new GCP project
	*  Click the navigation menu in the top left and select 'IAM & Admin	' > 'Service Accounts'
	*  On entry 'Compute Engine default service account', click the 'Options' menu (far right) and select 'Create key'
	*  Or, you can create a new service account entry with the following roles:
	  * Editor (project level)
	  * Cloud Datastore Owner
	  * Storage Object Viewer
	  * Genomics Service Agent
	*  Select 'JSON' and export and save the key locally
	*  Additionally, a 'read-only' service account is now used for streaming GCS assets to the client in some instances,
	so create a second service account and set the role to 'Storage Object Viewer' (see READ-ONLY SERVICE ACCOUNT at the
	bottom for a more detailed explanation on the role of this service account)
	*  Save this additional account locally next to the main service account.

* **Enable GCP APIs**: The following Google Cloud Platform APIs must be enabled:
	* Google Compute Engine API
	* Google Cloud APIs
	* Google Cloud Billing API
	* Google Cloud Storage JSON API
	* Google Cloud Genomics API

* **Registering your Service Account as a Terra user**: Once you have configured and booted your instance of the portal,
you will need to register your service account as a Terra user in order to create a billing project and create studies.
To do so:
	* Launch an instance of your portal (see [RUNNING THE CONTAINER](#running-the-container) below)
	* Create an admin user account (see [ADMIN USER ACCOUNTS](#admin-user-accounts) below)
	* Log in with the admin account, and select 'Admin Configurations' from the profile menu (top righthand corner)
	* At the bottom of the page, in the 'Other Tasks' dropdown, select 'Manage Main Service Account Terra Registration'
	and click 'Execute Task'
	* Fill out all form fields and submit
	* This must be done for both the 'main' and 'read-only' service accounts

* **Creating a Terra Project**: Once your OAuth audience has been authorized, and before you can create studies, you
will need to create a Terra project that will own all the workspaces created in the portal. To do this:
	* Create a [Google Billing Project](https://support.terra.bio/hc/en-us/articles/360026182251#How%20to%20create%20your%20own%20Google%20Billing%20Account).
	* Using the same Google account that owns the billing project, log into the portal and select 'My Billing Projects' from the profile menu.
	* Click 'New Billing Project' at the bottom of the page
		* Select your newly-created billing account
		* Provide a name for your project (no spaces allowed)
		* Click 'Create Billing Project'

* **IMPORTANT: Reboot your instance**
  * Once you have created your Terra billing project, you will need to restart your instance and pass the name of your
  Terra project into <code>bin/boot_docker</code> with <code>-N</code>


## RUNNING THE CONTAINER

Note: If you are developing locally and would like to leverage the hybrid Docker/local setup, see the section below on
[HYBRID DOCKER LOCAL DEVELOPMENT](#hybrid-docker-local-development).

Once the image has successfully built, all registration/configuration steps have been completed, use the following command
to start the container:

    bin/boot_docker -u (sendgrid username) -P (sendgrid password) -k (service account key path) -K (read-only service account key path) -o (oauth client id) -S (oauth client secret) -N (portal namespace) -m (mongodb hostname) -M (mongodb internal ip) -p (mongodb password)

This sets up several environment variables in your shell and then runs the following command:

    docker run --rm -it --name $CONTAINER_NAME -p 80:80 -p 443:443 -p 587:587 -h localhost -v $PROJECT_DIR:/home/app/webapp:rw -e PASSENGER_APP_ENV=$PASSENGER_APP_ENV -e MONGO_LOCALHOST=$MONGO_LOCALHOST -e MONGO_INTERNAL_IP=$MONGO_INTERNAL_IP -e SENDGRID_USERNAME=$SENDGRID_USERNAME -e SENDGRID_PASSWORD=$SENDGRID_PASSWORD -e SECRET_KEY_BASE=$SECRET_KEY_BASE -e PORTAL_NAMESPACE=$PORTAL_NAMESPACE -e SERVICE_ACCOUNT_KEY=$SERVICE_ACCOUNT_KEY -e OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID -e OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET -e SENTRY_DSN=$SENTRY_DSN -e GA_TRACKING_ID=$GA_TRACKING_ID -e TCELL_AGENT_APP_ID=$TCELL_AGENT_APP_ID -e T_CELL_SERVER_AGENT_API_KEY=$T_CELL_SERVER_AGENT_API_KEY -e TCELL_AGENT_API_KEY=$TCELL_AGENT_API_KEY gcr.io/broad-singlecellportal-staging/single-cell-portal:development

The container will then start running, and will execute its local startup scripts that will configure the application automatically.

You can also run the `bin/boot_docker` script in help mode by passing `-H` to print the help text which will show you how
to pass specific values to the above env variables.  *Note: running the shortcut script with an environment of 'production'
will cause the container to spawn headlessly by passing the `-d` flag, rather than `--rm -it`.*

### BROAD INSTITUTE CONFIGURATION

Broad Institute project members can load all project secrets from Vault and boot the portal directly by using the
`bin/load_env_secrets.sh` script, thereby skipping all of the configuration/registration steps in [DEPLOYING A PRIVATE INSTANCE](#local-development-or-deploying-a-private-instance)

    bin/load_env_secrets.sh -p (path/to/service/account.json) -s (path/to/portal/config) -r (path/to/readonly/service/account.json) -e (environment)

This script takes up to 7 parameters:

1. **VAULT_SECRET_PATH** (passed with -p): Path to portal configuration JSON inside Vault.
2. **SERVICE_ACCOUNT_PATH** (passed with -s): Path to GCP main service account configuration JSON inside Vault.
3. **READ_ONLY_SERVICE_ACCOUNT_PATH** (passed with -r): Path to GCP read-only service account configuration JSON inside Vault.
4. **COMMAND** (passed with -c): Command to execute after loading vault secrets.  Defaults to 'bin/boot_docker'
5. **PASSENGER_APP_ENV** (passed with -e; optional): Environment to boot portal in.  Defaults to 'development'.
6. **DOCKER VERSION TAG** (passed with -v): Sets the version tag of the portal Docker image to run.  Defaults to 'development'
7. **PORTAL_NAMESPACE** (passed with -n): Sets the value for the default Terra billing project.  Defaults to single-cell-portal-development

The script requires two command line utilities: [vault](https://www.vaultproject.io) and [jq](https://stedolan.github.io/jq/).
Please refer to their respective sites for installation instructions.

### DOCKER RUN COMMAND ENVIRONMENT VARIABLES
There are several variables that need to be passed to the Docker container in
order to run properly:
1. **CONTAINER_NAME** (passed with --name): This names your container to whatever you want.  This is useful when linking
containers.
1. **PROJECT_DIR** (passed with -v): This mounts your local working directory inside the Docker container.  Makes doing
local development via hot deployment possible.
1. **PASSENGER_APP_ENV** (passed with -e): The Rails environment you wish to load.  Can be either development, test, or
production (default is development).
1. **MONGO_LOCALHOST** (passed with -e): Hostname of your MongoDB server.  This can be a named host (if using a service)
or a public IP address that will accept traffic on port 27107
1. **MONGO_INTERNAL_IP** (passed with -e): Internal IP address of your MongoDB server.  This is for the Ingest Pipeline to
use when connecting to MongoDB if your firewalls are configured to only allow traffic from certain IP ranges.
1. **SENDGRID_USERNAME** (passed with -e): The username associated with a Sendgrid account (for sending emails).
1. **SENDGRID_PASSWORD** (passed with -e): The password associated with a Sendgrid account (for sending emails).
1. **SECRET_KEY_BASE** (passed with -e): Sets the Rails SECRET_KEY_BASE environment variable, used mostly by Devise in authentication for cookies.
1. **SERVICE_ACCOUNT_KEY** (passed with -e): Sets the SERVICE_ACCOUNT_KEY environment variable, used for making authenticated
API calls to Terra & GCP.
1. **READ_ONLY_SERVICE_ACCOUNT_KEY** (passed with -e): Sets the READ_ONLY_SERVICE_ACCOUNT_KEY environment variable, used
for making authenticated API calls to GCP for streaming assets to the browser.
1. **OAUTH_CLIENT_ID** (passed with -e): Sets the OAUTH_CLIENT_ID environment variable, used for Google OAuth2 integration.
1. **OAUTH_CLIENT_SECRET** (passed with -e): Sets the OAUTH_CLIENT_SECRET environment variable, used for Google OAuth2
1. **SENTRY_DSN** (passed with -e): Sets the SENTRY_DSN environment variable, for error reporting to [Sentry](https://sentry.io/)
integration.
1. **GA_TRACKING_ID** (passed with -e): Sets the GA_TRACKING_ID environment variable for tracking usage via
[Google Analytics](https://analytics.google.com) if you have created an app ID.
1. **TCELL_AGENT_APP_ID** (passed with -e): Sets the TCELL_AGENT_APP_ID environment variable to enable the TCell web application firewall (if enabled)
1. **TCELL_AGENT_API_KEY** (passed with -e): Sets the TCELL_AGENT_API_KEY environment variable to enable the TCell web application firewall client-side (if enabled)
1. **T_CELL_SERVER_AGENT_API_KEY** (passed with -e): Sets the T_CELL_SERVER_AGENT_API_KEY environment variable to enable 
   the TCell web application firewall server-side (if enabled). Note - this variable does not follow the normal "TCELL_*" 
   pattern to avoid issues with the client throwing warning messages to `STDOUT`
1. **PROD_DATABASE_PASSWORD** (passed with -e, for production deployments only): Sets the prod database password for accessing
the production database instance.  Only needed when deploying the portal in production mode.  See <code>config/mongoid.yml</code>
for more configuration information regarding the production database.


### RUN COMMAND IN DETAIL
The run command explained in its entirety:
* **--rm:** This tells Docker to automatically clean up the container after exiting.
* **-it:** Leaves an interactive shell running in the foreground where the output of Nginx can be seen.
* **--name CONTAINER_NAME:** This names your container to whatever you want.  This is useful when linking other Docker
containers to the portal container, or when connecting to a running container to check logs or environment variables.
The default is **single_cell**.
* **-p 80:80 -p 443:443 -p 587:587:** Maps ports 80 (HTTP), 443 (HTTPS), and 587 (smtp) on the host machine to the
corresponding ports inside the Docker container.
* **--link mongodb:mongodb**: Connects our webapp container to the mongodb container, creating a virtual hostname inside
the single_cell_docker container called mongodb.
* **-v [PROJECT_DIR]/:/home/app/webapp:** This mounts your local working directory inside the running Docker container
in the correct location for the portal to run.  This accomplishes two things:
    * Enables hot deployment for local development
    * Persists all project data past destruction of Docker container (since we're running with --rm), but not system-level
    log or tmp files.
* **-e PASSENGER_APP_ENV=[RAILS_ENV]:** The Rails environment.  Will default to development, so if you're doing a
production deployment, set this accordingly.
* **-e MONGO_LOCALHOST= [MONGO_LOCALHOST]:** Hostname of your MongoDB server.  This can be a named host (if using a service)
or a public IP address that will accept traffic on port 27107
* **-e MONGO_INTERNAL_IP= [MONGO_INTERNAL_IP]:** Internal IP address of your MongoDB server.  This is for the Ingest Pipeline to
use when connecting to MongoDB if your firewalls are configured to only allow traffic from certain IP ranges.  If you have
no such restrictions on your MongoDB instance, this should be set to the same as your MONGO_LOCALHOST.
* **-e SENDGRID_USERNAME=[SENDGRID_USERNAME] -e SENDGRID_PASSWORD=[SENDGRID_PASSWORD]:** The credentials for Sendgrid to
send emails. Alternatively, you could decide to not use Sendgrid and configure the application to use a different SMTP
server (would be done inside your environment's config file).
* **-e SECRET_KEY_BASE=[SECRET_KEY_BASE]:** Setting the SECRET_KEY_BASE variable is necessary for creating secure cookies
for authentication.  This variable automatically resets every time we restart the container.
* **-e SERVICE_ACCOUNT_KEY=[SERVICE_ACCOUNT_KEY]:** Setting the SERVICE_ACCOUNT_KEY variable is necessary for making
authenticated API calls to Terra and GCP.  This should be a file path **relative to the app root** that points to the
JSON service account key file you exported from GCP.
* **-e READ_ONLY_SERVICE_ACCOUNT_KEY=[READ_ONLY_SERVICE_ACCOUNT_KEY]:** Setting the READ_ONLY_SERVICE_ACCOUNT_KEY variable
is necessary for making authenticated API calls to GCP.  This should be a file path **relative to the app root** that points
to the JSON read-only service account key file you exported from GCP.
* **-e OAUTH_CLIENT_ID=[OAUTH_CLIENT_ID] -e OAUTH_CLIENT_SECRET=[OAUTH_CLIENT_SECRET]:** Setting the OAUTH_CLIENT_ID and
OAUTH_CLIENT_SECRET variables are necessary for allowing Google user authentication.  For instructions on creating OAuth
2.0 Client IDs, refer to the [Google OAuth 2.0 documentation](https://support.google.com/cloud/answer/6158849).
* **-e SENTRY_DSN=[SENTRY_DSN]:** Sets the SENTRY_DSN environment variable for error reporting to [Sentry](https://sentry.io/)
* **-e TCELL_AGENT_APP_ID=[TCELL_AGENT_APP_ID]:** Sets the TCELL_AGENT_APP_ID environment variable to enable the [TCell](https://tcell.io) web application firewall (if enabled)
* **-e TCELL_AGENT_API_KEY=[TCELL_AGENT_API_KEY]:** Sets the TCELL_AGENT_API_KEY environment variable to enable the [TCell](https://tcell.io) web application firewall client-side (if enabled)
* **-e T_CELL_SERVER_AGENT_API_KEY=[T_CELL_SERVER_AGENT_API_KEY]:** Sets the T_CELL_SERVER_AGENT_API_KEY environment variable to enable the [TCell](https://tcell.io) web application firewall server-side (if enabled)
* **-e GA_TRACKING_ID=[GA_TRACKING_ID]:** Sets the GA_TRACKING_ID environment variable for tracking usage via
[Google Analytics](https://analytics.google.com)
* **DOCKER_IMAGE_NAME**: This is the name of the Docker image the portal runs on, which is gcr.io/broad-singlecellportal-staging/single-cell-portal
* **DOCKER_IMAGE_VERSION** The version tag of the above Docker image.  Defaults to 'development', but can be overridden with `-D [tag]`
* ****

### INGEST PIPELINE AND NETWORK ENVIRONMENT VARIABLES
The Single Cell Portal handles ingesting data into MongoDB via an [ingest pipeline](https://github.com/broadinstitute/scp-ingest-pipeline)
that runs via the Google Genomics API (also known as the Pipelines API, or PAPI).  This API should have been enabled as
a previous step to this (see [DEPLOYING A PRIVATE INSTANCE](#local-development-or-deploying-a-private-instance)).

In order for the ingest pipeline to connect to MongoDB, and in addition to the variables relating to MongoDB as described
in [DOCKER RUN COMMAND ENVIRONMENT VARIABLES](#docker-run-command-environment-variables), there are two further environment
variables that may need to be set.  If you have deployed your MongoDB instance in GCP, and it is not on the "default"
network, then you must set the following two environment variables to allow the ingest pipeline to connect to MongoDB:

* GCP_NETWORK_NAME (the name of the network your MongoDB VM is deployed on)
* GCP_SUB_NETWORK_NAME (the name of the sub-network your MongoDB VM is deployed on)

Both of these pieces of information will be available in your VM's information panel in GCE.  To set these variables, as
there are not associated flags for bin/boot_docker, please export these two environment variables before calling any boot
scripts for the portal:


    export GCP_NETWORK_NAME=(name of network)
    export GCP_SUB_NETWORK_NAME=(name of sub-network)

    bin/boot_docker (rest of arguments)

This will set the necessary values inside the container.  **If your database is on the default network, this step is not
necessary.  If you are using a third-party MongoDB provider, please refer to their documentation regarding network access.**

**Single Cell Portal team members should set the associated values inside their vault configurations for their instance
of the portal.**

### ADMIN USER ACCOUNTS
The Single Cell Portal has the concept of a 'super-admin' user account, which will allow portal admins to view & edit any
studies in the portal for QA purposes, as well as receive certain admin-related emails.  This can only be enabled manually
through the console.

To create an admin user account:
* Start the portal locally (or ssh into production VM)
* Create a user account normally by logging in through the UI
* Connect to the running portal container: `docker exec -it single_cell bash`
* Enter the Rails console: `bin/rails console`
* Query for the desired user account: `user = User.find_by(email: '<email address here>')`
* Set the admin flag to true: `user.update(admin: true)`

## DEVELOPING OUTSIDE THE CONTAINER
Developing on SCP without a Docker container, while less robust, opens up some faster development paradigms, including live css/js reloading, faster build times, and byebug debugging in rails.  See [Non-containerized development README](./NON_CONTAINERIZED_DEV_README.md) for instructions

## HYBRID DOCKER LOCAL DEVELOPMENT
SCP team members can develop locally using Docker with a 'hybrid' setup that merges the speed of developing outside the 
container with the ease of using Docker for package/gem management.  This allows using `vite` for hot module replacement 
(HMR) along with all the other features of native Rails development, but uses `docker-compose` to build and deploy 
containers locally.  Both containers are built off of the `single-cell-portal:development` Docker image referenced above.

This setup will behave almost exactly like developing 
outside of the container - you can edit files in your IDE and have them updated in the container in real time, and any 
JS/CSS changes will automatically reload thanks to HMR without any page refresh.  The startup process (minus any 
`docker pull` latency) should only take ~30s, though if you update any JS dependencies it can take 2-3 minutes to run 
`yarn install` on boot depending on how constrained your local Docker installation is in terms of CPU/RAM.  You can 
reduce this latency by rebuilding the `single-cell-portal:development` Docker image locally.  See the section on 
[building the Docker image](#pullingbuilding-the-docker-image) above for more information.

### USING DOCKER COMPOSE LOCALLY
To leverage this setup, there are two shell scripts for setup and cleanup, respectively.  To start the local instance, 
run:

    bin/docker-compose-setup.sh

This will pull all necessary secrets from `vault` and write env files to pass to Docker, then create two containers 
locally: `single_cell` (application server), and `single_cell_vite` (vite dev server). Both containers will install 
their dependencies automatically if you have updated any gems or JS packages and then start their required services.  In 
addition to the Rails server, the `single_cell` container will run any required migrations and start `Delayed::Job` on 
startup.  Both containers can be stopped by pressing `Ctrl-C`.  This will not remove either container, and they can both 
be restarted with the same command.

You can also start these containers headlessly by passing `-d`.  This runs the same startup commands, but will not 
attach `STDOUT` from the containers to the terminal.  When using this option, note that it will take between 30-60 
seconds before the portal instance is available at `https://localhost:3000/single_cell`.

    bin/docker-compose-setup.sh -d

To stop both services and clean up the Docker environment, run:

    bin/docker-compose-cleanup.sh

This will remove both containers, their dependent volumes, and reset any local configuration files to their non-Dockerized 
format.

## UPDATING JAVASCRIPT PEER/INDIRECT DEPENDENCIES
Since `yarn` does not automatically upgrade peer/indirect dependencies automatically (it will only update packages declared 
in package.json), The following snippet can be used to update dependencies not covered in `yarn upgrade`:

https://gist.github.com/pftg/fa8fe4ca2bb4638fbd19324376487f42

## CACHING IN LOCAL DEVELOPMENT
Single Cell Portal employs action caching for all data visualization requests, such as viewing cluster, violin, or dot 
plots.  As such, making code changes during local development may not always reflect the most recent changes as a particular 
request may have already been cached by the server.

In order to turn caching on/off dynamically without having to restart the server, developers can run the following command 
from the terminal:

    bin/rails dev:cache

This will add/remove a file in the `tmp` directory called `caching-dev.txt` that will govern whether or not action caching 
is enabled.  NOTE: if you are developing inside Docker, you must run this command inside the running container.

If you want to clear the entire cache for the portal while running, you can enter the Rails console and run the `Rails.cache.clear` 
command which will clear the entire Rails cache (actions and assets, such as CSS and JS assets):

    root@localhost:/home/app/webapp# bin/rails c
    Loading development environment (Rails 5.2.4.4)
    2.6.5 :001 > Rails.cache.clear
   
This will then return a list of cache paths that have been deleted.  If you encounter a `Directory not empty` error when 
running this command, simply retry until it succeeds, as it usually only takes one or two attempts.

## TESTS

### UNIT & INTEGRATION TESTS
There is a unit & integration test framework for the Single Cell Portal that is run using the built-in test Rails
harness, which uses [Test::Unit](https://github.com/test-unit/test-unit) and [minitest-rails](https://github.com/blowmage/minitest-rails).
These tests can be run natively in Ruby once all project secrets have been loaded.  Each 
test handles its own setup/teardown, and no test data needs to be seeded in order to run tests.

To run all unit/integration tests:
```
bin/rails test
```

To run a specific unit/integration test suite (like the search API integration suite):
```
bin/rails test test/api/search_controller_test.rb
```

To run individual tests in a give suite:
```
bin/rails test test/api/search_controller_test.rb -n /facet/ # run all tests with the word 'facet' in the name
bin/rails test test/api/search_controller_test.rb -n 'test_should_search_facet_filters' # run exact match on name
```

Additionally, these tests can be run automatically in Docker.  To run the unit & integration test suite, the `boot_docker` 
script can be used:

    bin/boot_docker -e test -k (service account key path) -K (read-only service account path)

This will boot a new instance of the portal in test mode and run all associated tests, *not including the UI test suite*.

If you are a Broad engineer developing the canonical Single Cell Portal, run unit and integration tests like so:

    bin/load_env_secrets.sh -e test -p vault/path/to/your/development/scp_config.json -s vault/path/to/your/development/scp_service_account.json -r vault/path/to/your/development/read_only_service_account.json

It is also possible to run individual tests suites by passing the following parameters to `boot_docker`. To run all tests
in a single suite:

    bin/boot_docker -e test -k (service account key path) -K (read-only service account path) -t (relative/path/to/tests.rb)

For instance, to run the FireCloudClient integration test suite:

    bin/boot_docker -e test -t test/integration/fire_cloud_client_test.rb (... rest of parameters)

You can also only run a subset of matching tests by passing -R /regexp/.  The following example would run all tests with
the word 'workspace' in their test name:

    bin/boot_docker -e test -t test/integration/fire_cloud_client_test.rb -R /workspace/ (... rest of parameters)

It is also possible to pass a fully-qualified single-quoted name to run only a single test.  The following example would
run only the test called `'test_workspaces'` in `test/integration/fire_cloud_client_test.rb`

    bin/boot_docker -e test -t test/integration/fire_cloud_client_test.rb -R 'test_workspaces' (... rest of parameters)

### UI REGRESSION SUITE
#### DEPRECATED
Do not use test/ui_test_suite.rb as it no longer corresponds to most active UI features.

## GOOGLE DEPLOYMENT

### PRODUCTION

The official production Single Cell Portal is deployed in Google Cloud Platform.  Only Broad Institute Single Cell Portal
team members have administrative access to this instance.  If you are a collaborator and require access, please email
[scp-support@broadinstitute.zendesk.com](mailto:scp-support@broadinstitute.zendesk.com).

For Single Cell Portal staff: please refer to the SCP playbook and Jenkins server on how to deploy to production.

### NON-BROAD PRODUCTION DEPLOYMENTS

If you are deploying your own production instance in a different project, the following VM/OS configurations are recommended:
* VM: n1-highmem-4 (4 vCPUs, 26 GB memory)
* OS: Ubuntu 18.04 (Bionic Beaver) or later
* Disks: Two standard persistent disks, one for the operating system (boot disk), and a second "data" disk for checking out
the portal  source code. It is recommended to provision at least 100GB for the "data" disk to allow enough temp space for
multiple concurrent file uploads.

For more information on formatting and mounting additional persistent disks to a GCP VM, please read the
[GCP Documentation](https://cloud.google.com/compute/docs/disks/add-persistent-disk#formatting).

To deploy or access an instance of Single Cell Portal in production mode:
* Go to the your corresponding [GCP Project](https://console.cloud.google.com)
* Select "Compute Engine" from the top-left nav dropdown
* Click the SSH button under the Connect heading next to your production VM (this will launch an SSH tunnel in a browser window)
* Once connected, switch to root via `sudo -i`.
* Change directory to where the portal is running, for instance: `cd /home/docker-user/deployments/single_cell_portal`
* Switch to the Docker user: `sudo -u docker-user -Hs`
* Get latest source code from GitHub: `git pull origin master`
* Exit Docker user to return to root: `exit`
* Ensure no uploads are occuring: `tail -n 1000 log/production.log`
* Put the portal in maintenance mode: `bin/enable_maintenance.sh on`
* Stop the portal: `docker stop single_cell`
* Remove the container instance: `docker rm single_cell`
* Launch a new instance of the portal with the updated container (please refer to the
[bin/boot_docker](https://github.com/broadinstitute/single_cell_portal_core/blob/master/bin/boot_docker) script for more
information regarding all possible arguments as they are not all listed here):


    bin/boot_docker -u (sendgrid username) -P (sendgrid password) -k (service account key path) -K (read-only service account key path) -o (oauth client id) -S (oauth client secret) -N (portal namespace) -m (mongodb hostname) -M (mongodb internal ip) -p (mongodb password) -e production

* Once Nginx is running again (i.e. you see "Passenger core online" in Docker logs), take off maintanence mode via `bin/enable_maintenance.sh off`

#### PRODUCTION DOCKER COMMANDS

* To bounce the portal: `docker restart single_cell`
* To stop the portal: `docker stop single_cell`
* To remove the portal container: `docker rm single_cell`
* To connect to the running portal container: `docker exec -it single_cell bash`
* View Docker logs: `docker logs -f single_cell`

When you launch a new instance of the portal, you should get a response that is looks like a long hexadecimal string -
this is the instance ID of the new container.  Once the container is running, you can connect to it with the `docker exec`
command and perform various Rails-specific actions, like:

* Re-index the database: `bin/rake RAILS_ENV=production db:mongoid:create_indexes`
* Launch the Rails console (to inspect database records, for instance): `bin/rails console -e production`


### STAGING

There is also a staging instance of the Single Cell Portal used for testing new functionality in a production-like setting.
The staging instance URL is https://single-cell-staging.broadinstitute.org/single_cell

The run command for staging is identical to that of production, with the exception of passing `-e staging` as the environment,
and any differing values for hostnames/client secrets/passwords as needed.

For Single Cell Portal staff: please refer to the SCP playbook and Jenkins server on how to deploy to staging.

*Note: This instance is usually turned off to save on compute costs, so there is no expectation that it is up at any given time*

### TERRA INTEGRATION

The Single Cell Portal stores uploaded study data files in [Terra](https://app.terra.bio/)
workspaces, which in turn store data in GCP buckets.  This is all managed through a GCP service account which in turn
owns all portal workspaces and manages them on behalf of portal users.  All portal-related workspaces are within the
`single-cell-portal` namespace (or what the PORTAL_NAMESPACE environment variable is set to), which should be noted is a
separate project from the one the portal itself operates out of.

When a study is created through the portal, a call is made to the Terra API to provision a workspace and set the ACL
to allow owner access to the user who created the study, and read/write access to any designated shares.  Every Terra
workspace comes with a GCP storage bucket, which is where all uploaded files are deposited.  No ACLs are set on individual
files as all permissions are inherited from the workspace itself.  Files are first uploaded temporarily locally to the
portal (so that they can be parsed if needed) and then sent to the workspace bucket in the background after uploading and
parsing have completed.

If a user has not signed up for a Terra account, they will receive and invitation email from Terra asking them to
complete their registration.  While they will be able to interact with their study/data through the portal without completing
their registration, they will not be able to load their Terra workspace or access the associated GCP bucket until they
have done so.

Deleting a study will also delete the associated workspace, unless the user specifies that they want the workspace to be
persisted. New studies can also be initialized from an existing workspace (specified by the user during creation) which will
synchronize all files and permissions.

## OTHER FEATURES

### ADMIN CONTROL PANEL, DOWNLOAD QUOTAS & ACCESS REVOCATION

All portal users are required to authenticate before downloading data as we implement daily per-user quotas.  These are
configurable through the admin control panel which can be accessed only by portal admin accounts (available through the
profile menu or at /single_cell/admin).

There are currently 7 configuration actions:

* Daily download quota limit (defaults to 2 terabytes, but is configurable to any amount, including 0)
* Manage Terra access (can disable local access, compute access, or all access)
* Unlock orphaned jobs (any background jobs that were running during a portal restart are locked until this option is used)
* Refresh API clients (force the FireCloudClient class to renew all access tokens)
* Manage both service account Terra profiles (register or update the Terra profile associated with the main &
readonly portal service accounts).
* See the current Terra API status (for all services)
* Synchronize the portal user group (if set, will add all users to user group)


#### READ-ONLY SERVICE ACCOUNT

The read-only service account is a GCP service account that is used to grant access to GCS objects from 'public' studies
so that they can be rendered client-side for the user.  Normally, a user would not have access to these objects directly
in GCS as access is federated by the main service account on public studies (private studies have explicit grants, and
therefore user access tokens are used).  However, access tokens granted from the main service account would have project
owner permissions, so they cannot be used safely in the client.  Therefore, a read-only account is used in this instance
for operational security.

This account is not required for main portal functionality to work, but certain visualizations (Ideogram.js & IGV.js)
will not be enabled unless this account is enabled.

To enable the read-only service account:

1. Create a new service account in your GCP project and grant it 'Storage Object Viewer' permission (see 'GCP Service
Account keys' under [DEPLOYING A PRIVATE INSTANCE](#local-development-or-deploying-a-private-instance) for more information)

1. Export the JSON credentials to a file and save inside the portal home directory.
1. When booting your instance (via `bin/boot_docker`), make sure to pass `-K (/path/to/readonly/credentials.json)`
1. Once the portal is running, navigate to the Admin Control Panel with an admin user account
1. Select 'Manage Read-Only Service Account Terra Registration' from the 'Other Tasks' menu and click 'Execute'
1. Fill out all form fields and submit.
1. Once your new service account is registered, create a Config Option of the type 'Read-Only Access Control'
1. Set the type of value to 'Boolean', and set the value to 'Yes', and save


This will have the effect of adding shares to all public studies in your instance of the portal for the read-only service
account with 'View' permission.  This will then enable the portal to stream certain kinds of files (BAM files, for instance)
back to the client for visualization without the need for setting up and external proxy server.

To revoke this access, simply edit the configuration setting and set the value
to 'No'.

#### TERRA ACCESS SETTINGS

Disabling all Terra access is achieved by revoking all access to studies directly in Terra and using the portal
permission map (study ownership & shares) as a backup cache.  This will prevent anyone from downloading data either through
the portal or directly from the workspaces themselves.  This will have the side effect of disallowing any edits to studies
while in effect, so this feature should only be used as a last resort to curtail runaway downloads.  While access is disabled,
only the portal service account will have access to workspaces.

Disabling compute access will set all user access permissions to READER, thus disabling computes.

Disabling local access does not alter Terra permissions, but prevents users from accessing the 'My studies' page and
uploading data through the portal.  Downloads are still enabled, and normal front-end actions are unaffected.

Re-enabling Terra access will restore all permissions back to their original state.

#### SYNTHETIC DATA

Synthetic study data for testing and demonstrating portal features is configured in db/seed/synthetic_studies.  See the [Synthetic study README](./db/seed/synthetic_studies/README.md)

### MAINTENANCE MODE

The production Single Cell portal has a defined maintenance window every **Thursday from 12-2PM EST**.  To minimize user
dispruption when doing updates during that window (or hot fixes any other time) the portal has a 'maintenance mode' feature
that will return a 503 and redirect all incoming traffic to a static maintenance HTML page.

To use this feature, run the `bin/enable_maintenance.sh [on/off]` script accordingly.

### RUBOCOP

This project is configured to use [RuboCop](https://docs.rubocop.org/rubocop/index.html) for static code analysis.  There 
is a [shell script](.bin/run_rubocop.sh) that allows for running RuboCop only on files that have been edited since the last 
commit to Git.  Configuration for RuboCop can be found [here](.rubocop.yml), or referenced from RuboCop's 
[default configuration](https://github.com/rubocop-hq/rubocop/blob/master/config/default.yml).

#### USAGE

To run RuboCop normally on all your local changes:

    bin/run_rubocop.sh
    
Run in "lint-only" mode (does not enforce style checks):

    bin/run_rubocop.sh -l
    
Run in "safe auto-correct" mode (will automatically correct any issues, where possible):

    bin/run_rubocop.sh -a

The `-a` and `-l` flags can be used together.  Usage text for the script can be printed with `-h`.
