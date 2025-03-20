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

THIS_DIR="$(cd "$(dirname "$BASH_SOURCE")"; pwd)"
BASE_DIR="$(dirname $THIS_DIR)"

export PASSENGER_APP_ENV=test
export RUBYOPT=--disable-frozen-string-literal

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
  echo "Precompiling assets, yarn and vite..."
  export NODE_OPTIONS="--max-old-space-size=4096 --unhandled-rejections=warn"
  if [[ "$CI" == true ]]; then
    git config --global --add safe.directory $(pwd)
  fi
  git checkout .
  RAILS_ENV=test NODE_ENV=test bin/rails assets:precompile
fi

echo "Generating indexes..."
bundle exec rake RAILS_ENV=test db:mongoid:create_indexes
echo "Indexes initialized"

echo "Running specified unit & integration tests..."

# we're piping test results to other commands, so setting pipefail will preserve the failing exit code even if it
# is not the last command in the pipe
set -o pipefail
# only run yarn ui-test if we haven't specified a single ruby test suite to run
if [[ "$TEST_FILEPATH" == "" ]]; then
  # "2>&1 | tee yarn_test.log" puts the output of the tests both into stdout and the yarn_test.log file
  yarn ui-test 2>&1 | tee yarn_test.log
  RETURN_CODE=$? # immediately capture exit code to prevent this from getting clobbered
fi

# configure and invoke command for rails tests
if [[ "$MATCHING_TESTS" != "" ]] && [[ "$TEST_FILEPATH" != "" ]]; then
  RAILS_ENV=test bin/rails test TEST_FILEPATH -n $MATCHING_TESTS 2>&1 | tee rails_test.log
elif [[ "$TEST_FILEPATH" != "" ]]; then
  RAILS_ENV=test bin/rails test $TEST_FILEPATH 2>&1 | tee rails_test.log
else
  RAILS_ENV=test bin/rails test 2>&1 | tee rails_test.log
fi
code=$?

# consolidate and format test results into test_summary.txt
printf "*** Yarn test failures ***\n" > test_summary.txt
grep "FAIL\|✕" yarn_test.log >> test_summary.txt
printf "\n" >> test_summary.txt
printf "*** Rails test failures ***\n" >> test_summary.txt
# find the lines after the Failure/Error text, which have the actual test names that failed.
# then strip out the Failure/Error lines, as well as the grep-inserted '--' lines
# then prefix them with '  ' so they are easier to distinguish
# we also grab the blank line before each Failure, so that the results are spaced out in the final output
grep -A2 -B1 ")\sFailure:\|)\sError:" rails_test.log | \
    grep -v ")\sFailure:\|)\sError:\|--" >> test_summary.txt

# the return code will be 1 if either the js or rails tests exited with 1
(( RETURN_CODE = RETURN_CODE || $code ))

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
  printf "\n### FAILURES and ERRORS ###\n"
  # output summary file to console, with indents around the non-header lines added for readability
  sed 's/^[^\*]/  &/' test_summary.txt
fi

echo "Exiting with code: $RETURN_CODE"
exit $RETURN_CODE
