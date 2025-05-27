#!/bin/bash

usage=$(
cat <<EOF

### shell script to load secrets from GSM and execute command ###
$0

[OPTIONS]
-k VALUE  set the SERVICE_ACCOUNT_KEY variable, necessary for making authenticated calls to Terra Orchestration API
-v VALUE  set the version of the Docker image to load (defaults to 'development')
-e VALUE  set the environment to run tests in (defaults to "test")
-d        set to run smoke test outside of Docker
EOF
)

DOCKER_IMAGE_NAME="gcr.io/broad-singlecellportal-staging/single-cell-portal"
DOCKER_IMAGE_VERSION="development"
PASSENGER_APP_ENV="test"
NON_DOCKERIZED="false"
# disable warnings about frozen literals
export RUBYOPT=--disable-frozen-string-literal

while getopts "k:e:v:d" OPTION; do
case $OPTION in
  k)
    SERVICE_ACCOUNT_KEY="$OPTARG"
    ;;
  e)
    PASSENGER_APP_ENV="$OPTARG"
    ;;
  v)
    DOCKER_IMAGE_VERSION="$OPTARG"
    ;;
  d)
    NON_DOCKERIZED=true
    ;;
  *)
    echo "ignoring unused flags, variables still passed"
    ;;
  esac
done

if [[ "$NON_DOCKERIZED" = "true" ]]; then
  ORCH_SMOKE_TEST=true bin/rails test test/integration/external/fire_cloud_client_test.rb
else
  docker run --rm -t --name single_cell_test -h localhost -v "$(pwd):/home/app/webapp:consistent" \
    --mount type=volume,dst=/home/app/webapp/node_modules \
    -e PASSENGER_APP_ENV="$PASSENGER_APP_ENV" -e MONGO_LOCALHOST="$MONGO_LOCALHOST" \
    -e MONGO_INTERNAL_IP="$MONGO_INTERNAL_IP" -e PROD_DATABASE_PASSWORD="$PROD_DATABASE_PASSWORD" \
    -e ORCH_SMOKE_TEST=true -e SERVICE_ACCOUNT_KEY="$SERVICE_ACCOUNT_KEY" \
    -e PORTAL_NAMESPACE="$PORTAL_NAMESPACE" -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
    -e GOOGLE_CLOUD_KEYFILE_JSON="$GOOGLE_CLOUD_KEYFILE_JSON" -e GOOGLE_PRIVATE_KEY="$GOOGLE_PRIVATE_KEY" \
    -e GOOGLE_CLIENT_EMAIL="$GOOGLE_CLIENT_EMAIL" -e GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    -e GOOGLE_CLOUD_PROJECT="$GOOGLE_CLOUD_PROJECT" -e CODECOV_TOKEN="$CODECOV_TOKEN" \
    -e RAILS_LOG_TO_STDOUT="$RAILS_LOG_TO_STDOUT" -e CI="$CI" \
    -e GOOGLE_PROJECT_NUMBER="$GOOGLE_PROJECT_NUMBER" $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION \
    bin/rails test test/integration/external/fire_cloud_client_test.rb
fi

