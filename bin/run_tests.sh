#!/usr/bin/env bash

# script that is called when booting portal in test environment to run all unit tests and integration tests in the correct order as some
# tests change downstream behavior after they've run
#
# can take the following arguments:
#
# -t filepath   Run all tests in the specified file
# -R regex      Run all matching tests in the file specified with -t
# -l            Invoke rails_local_setup.rb to configure environment before running tests (if developing non-Dockerized)

LOCAL_SETUP="false"
while getopts "t:R:l" OPTION; do
case $OPTION in
  t)
    TEST_FILEPATH="$OPTARG"
    ;;
  R)
    MATCHING_TESTS="$OPTARG"
    ;;
  l)
    LOCAL_SETUP="true"
    ;;
  esac
done
start=$(date +%s)
RETURN_CODE=0
FAILED_COUNT=0

THIS_DIR="$(cd "$(dirname "$BASH_SOURCE")"; pwd)"
BASE_DIR="$(dirname $THIS_DIR)"

function setup_burp_cert {
  if [ -n "$BURP_PROXY" ]; then
    # we will store Burp certificate here
    local BURP_CERT="/usr/local/share/ca-certificates/burp.crt"

    # fetch Burp certificate from Burp proxy localhost endpoint and store it into $BURP_CERT
    curl -s --proxy "$BURP_PROXY" burp/cert | openssl x509 -inform DER -out "$BURP_CERT"

    # update system-wide certificate store
    update-ca-certificates

    # override cacert store for httpclient package (used by Google libraries)
    ln -sf "$BURP_CERT" /usr/local/rvm/gems/default/gems/httpclient-*/lib/httpclient/cacert.pem

    # override cafile for Yarn (used during package fetching)
    yarn config set cafile "$BURP_CERT" -g

    # set http_proxy variable, which will make HTTP connections go through the Burp proxy
    export http_proxy="$BURP_PROXY"
  fi
}

export PASSENGER_APP_ENV=test

function clean_up {
  echo "Cleaning up..."
  bundle exec bin/rails runner -e test "StudyCleanupTools.destroy_all_studies_and_workspaces" || { echo "FAILED to delete studies and workspaces" >&2; exit 1; } # destroy all studies/workspaces to clean up any files
  bundle exec bin/rails runner -e test "BigQueryClient.clear_bq_table" || { echo "FAILED to clear BigQuery table" >&2; exit 1; } # make sure BQ table is cleared
  # only do workspace cleanup in CI run as this would delete workspaces from a local instance
  if [[ "$CI" = true ]]; then
      bundle exec bin/rails runner -e test "StudyCleanupTools.delete_all_orphaned_workspaces" || { echo "FAILED to delete orphaned workspaces" >&2; exit 1; } # remove any orphaned workspaces from previous failures
  fi
  bundle exec rake RAILS_ENV=test db:purge
  echo "...cleanup complete."
}

TMP_PIDS_DIR="$BASE_DIR/tmp/pids"
rm ./log/test.log
if [[ ! -d "$TMP_PIDS_DIR" ]]
then
  echo "*** MAKING tmp/pids DIR ***"
  mkdir -p "$TMP_PIDS_DIR" || { echo "FAILED to create $TMP_PIDS_DIR" >&2; exit 1; }
  echo "*** COMPLETED ***"
fi

# export secrets for local testing, and ensure delayed_job is not running
# if not testing locally, remove any dangling pid files
if [[ $LOCAL_SETUP == "true" ]]; then
  echo "setting up environment for local testing"
  $BASE_DIR/rails_local_setup.rb -e $PASSENGER_APP_ENV
  . $BASE_DIR/config/secrets/.source_env.bash
  rm $BASE_DIR/config/secrets/.source_env.bash
  pids=$(ls $TMP_PIDS_DIR/delayed_job.*.pid | xargs cat)
  for pid in $pids
  do
    kill -9 $pid
  done
else
  rm -f "$TMP_PIDS_DIR/delayed_job.*.pid"
fi

setup_burp_cert
clean_up

echo "*** STARTING DELAYED_JOB for $PASSENGER_APP_ENV env ***"
bin/delayed_job restart $PASSENGER_APP_ENV -n 6 || { echo "FAILED to start DELAYED_JOB" >&2; exit 1; } # WARNING: using "restart" with environment of test is a HACK that will prevent delayed_job from running in development mode, for example

# If we're only running Ruby tests, then don't compile JavaScript
#
# Note: there are some Ruby integration tests that do require JS assets to be
# compiled.  Any test that issues a local HTTP request to a non-API endpoints
# (such as StudyCreationTest or TaxonsControllerTest) will cause webpack to
# autocompile assets if they are not already present. This change won't result
# in an error; this is just an FYI that static assets are needed for more
# than just `yarn ui-test`.
if [[ "$TEST_FILEPATH" == "" ]]; then
  echo "Precompiling assets, yarn and webpacker..."
  export NODE_OPTIONS="--max-old-space-size=4096"
  RAILS_ENV=test NODE_ENV=test bin/bundle exec rake assets:clean
  RAILS_ENV=test NODE_ENV=test yarn install --force --trace
  RAILS_ENV=test NODE_ENV=test bin/bundle exec rake assets:precompile
fi

echo "Generating random seed, seeding test database..."
RANDOM_SEED=$(openssl rand -hex 16)
echo $RANDOM_SEED > "$BASE_DIR/.random_seed"
bundle exec rake RAILS_ENV=test db:seed || { echo "FAILED to seed test database!" >&2; exit 1; }
bundle exec rake RAILS_ENV=test db:mongoid:create_indexes
echo "Database initialized"
echo "Launching tests using seed: $RANDOM_SEED"

echo "Running specified unit & integration tests..."
# only run yarn ui-test if we haven't specified a single ruby test suite to run
if [[ "$TEST_FILEPATH" == "" ]]; then
  yarn ui-test
  code=$? # immediately capture exit code to prevent this from getting clobbered
  if [[ $code -ne 0 ]]; then
    RETURN_CODE=$code
    first_test_to_fail=${first_test_to_fail-"yarn ui-test"}
    ((FAILED_COUNT++))
  fi
fi

# configure and invoke command for rails tests
if [[ "$MATCHING_TESTS" != "" ]] && [[ "$TEST_FILEPATH" != "" ]]; then
  RAILS_ENV=test bin/rails test TEST_FILEPATH -n $MATCHING_TESTS
elif [[ "$TEST_FILEPATH" != "" ]]; then
  RAILS_ENV=test bin/rails test $TEST_FILEPATH
else
  RAILS_ENV=test bin/rails test test/integration/synthetic_study_populator_test.rb
fi
code=$?
if [[ $code -ne 0 ]]; then
  RETURN_CODE=$code
  first_test_to_fail=${first_test_to_fail-"rails test"}
  ((FAILED_COUNT++))
fi
if [[ "$CODECOV_TOKEN" != "" ]] && [[ "$CI" == "true" ]]; then
  echo "uploading all coverage data to codecov"
  bash <(curl -s https://raw.githubusercontent.com/broadinstitute/codecov-bash-uploader/main/codecov-verified.bash)
fi

clean_up
end=$(date +%s)
difference=$(($end - $start))
min=$(($difference / 60))
sec=$(($difference % 60))
echo "Total elapsed time: $min minutes, $sec seconds"
if [[ $RETURN_CODE -eq 0 ]]; then
  printf "\n### All test suites PASSED ###\n\n"
else
  printf "\n### There were $FAILED_COUNT errors/failed test suites in this run, starting with $first_test_to_fail ###\n\n"
fi

echo "Exiting with code: $RETURN_CODE"
exit $RETURN_CODE
