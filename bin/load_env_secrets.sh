#! /bin/bash

# load_env_secrets.sh
#
# shell script to export environment variables from GSM or a JSON configuration file and then boot portal
# requires the jq utility: https://stedolan.github.io/jq/ and all necessary secrets loaded into the
# Secret Manager in GCP: https://console.cloud.google.com/security/secret-manager

# usage error message
usage=$(
cat <<EOF

### shell script to load secrets from GSM and execute command ###
$0

[OPTIONS]
-p VALUE	set the name of the main SCP config in GSM
-s VALUE	set the name of the service account credentials object in GSM
-r VALUE	set the name of the 'read-only' service account credentials object in GSM
-g VAULE  set the name of the GCP project from which to load secrets
-c VALUE	command to execute after loading secrets (defaults to bin/boot_docker, please wrap command in 'quotes' to ensure proper execution)
-e VALUE	set the environment to boot the portal in (defaults to development)
-v VALUE  set the version of the Docker image to load (defaults to latest)
-n VALUE	set the value for PORTAL_NAMESPACE (defaults to single-cell-portal-development)
-H COMMAND	print this text
EOF
)

# defaults
PASSENGER_APP_ENV="development"
COMMAND="bin/boot_docker"
THIS_DIR="$(cd "$(dirname "$0")"; pwd)"
CONFIG_DIR="$THIS_DIR/../config"
SPECIAL_CMD="false"
GOOGLE_CLOUD_PROJECT=$(gcloud info --format="value(config.project)")
while getopts "p:s:r:g:c:e:v:n:H" OPTION; do
case $OPTION in
  p)
    SCP_CONFIG_NAME="$OPTARG"
    ;;
  s)
    DEFAULT_SA_KEYFILE="$OPTARG"
    ;;
  r)
    READ_ONLY_SA_KEYFILE="$OPTARG"
    ;;
  g)
    GOOGLE_CLOUD_PROJECT="$OPTARG"
    ;;
  c)
    COMMAND="$OPTARG"
    SPECIAL_CMD="true"
    ;;
  v)
    DOCKER_IMAGE_TAG="$OPTARG"
    ;;
  e)
    PASSENGER_APP_ENV="$OPTARG"
    ;;
  n)
    PORTAL_NAMESPACE="$OPTARG"
    ;;
  H)
    echo "$usage"
    exit 0
    ;;
  *)
    echo "unrecognized option"
    echo "$usage"
    ;;
  esac
done
if [[ -z $DEFAULT_SA_KEYFILE ]] && [[ -z $SCP_CONFIG_NAME ]] ; then
  echo "You must supply the DEFAULT_SA_KEYFILE [-c] & SCP_CONFIG_NAME [-p] (or CONFIG_PATH_PATH [-f]) to use this script."
  echo ""
  echo "$usage"
  exit 1
fi

#  clear this environment variable just in case this terminal was used for local development
unset NOT_DOCKERIZED
BASE_GSM_COMMAND="gcloud secrets versions access latest --project=$GOOGLE_CLOUD_PROJECT"

if [[ -n $SCP_CONFIG_NAME ]] ; then
  # load raw secrets from GSM
  VALS=$($BASE_GSM_COMMAND --secret=$SCP_CONFIG_NAME)

  # for each key in the secrets config, export the value
  for key in $(echo $VALS | jq --raw-output 'keys[]')
  do
    echo "setting value for: $key"
    curr_val=$(echo $VALS | jq --raw-output .$key)
    # honor PORTAL_NAMESPACE from the environment, if present
    if [[ "$PORTAL_NAMESPACE" != "" && "$key" = "PORTAL_NAMESPACE" ]] ; then
      echo "honoring current value of PORTAL_NAMESPACE: $PORTAL_NAMESPACE"
      export PORTAL_NAMESPACE=$PORTAL_NAMESPACE
    else
      export $key=$curr_val
    fi
  done
fi
# now load service account credentials
if [[ -n $DEFAULT_SA_KEYFILE ]] ; then
  echo "setting value for: GOOGLE_CLOUD_KEYFILE_JSON"
  CREDS_VALS=$($BASE_GSM_COMMAND --secret=$DEFAULT_SA_KEYFILE)
  JSON_CONTENTS=$(echo $CREDS_VALS | jq --raw-output)
  echo "*** WRITING MAIN SERVICE ACCOUNT ***"
  SERVICE_ACCOUNT_FILEPATH="$CONFIG_DIR/.scp_service_account.json"
  echo $JSON_CONTENTS >| $SERVICE_ACCOUNT_FILEPATH
  COMMAND=$COMMAND" -k /home/app/webapp/config/.scp_service_account.json"
  JSON_CONTENTS=$(echo $CREDS_VALS | jq --raw-output)
  echo "setting value for: GOOGLE_CLOUD_PROJECT"
  export GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
fi

# now load public read-only service account credentials
if [[ -n $READ_ONLY_SA_KEYFILE ]] ; then
  echo "setting value for: READ_ONLY_GOOGLE_CLOUD_KEYFILE_JSON"
  READ_ONLY_CREDS_VALS=$($BASE_GSM_COMMAND --secret=$READ_ONLY_SA_KEYFILE)
  READ_ONLY_JSON_CONTENTS=$(echo $READ_ONLY_CREDS_VALS | jq --raw-output)
  echo "*** WRITING READ ONLY SERVICE ACCOUNT CREDENTIALS ***"
  READONLY_FILEPATH="$CONFIG_DIR/.read_only_service_account.json"
  echo $READ_ONLY_JSON_CONTENTS >| $READONLY_FILEPATH
  COMMAND=$COMMAND" -K /home/app/webapp/config/.read_only_service_account.json"
fi

# check for override of default bin/boot_docker command
if [[ "$SPECIAL_CMD" = "true" ]] ; then
  echo "RUNNING NON-STANDARD COMMAND: $COMMAND"
  $COMMAND -e $PASSENGER_APP_ENV -v $DOCKER_IMAGE_TAG
else
  # insert connection information for MongoDB if this is not a CI run
  COMMAND=$COMMAND" -m $MONGO_LOCALHOST -p $PROD_DATABASE_PASSWORD -M $MONGO_INTERNAL_IP"

  # Filter credentials from log, just show Rails environment and Terra billing project
  echo "BOOTING PORTAL WITH: -e $PASSENGER_APP_ENV -N $PORTAL_NAMESPACE"
  # execute requested command
  $COMMAND -D $DOCKER_IMAGE_TAG -e $PASSENGER_APP_ENV -N $PORTAL_NAMESPACE
fi
