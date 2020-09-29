#!/usr/bin/env bash

# run_rubocop.sh - Bash one-liner to run RuboCop on all local changes not yet staged for commit to Git
# refer to https://docs.rubocop.org/rubocop/index.html for more information on RuboCop usage

usage=$(
cat <<EOF
USAGE:
   $(basename $0) [<options>]

### Bash one-liner to run RuboCop on all local changes not yet staged for commit to Git ###

[OPTIONS]
-l  Run RuboCop in "lint-only" mode (does not run style checks)
-a  Use RuboCop "safe auto-correct" mode
-h  Print this text
EOF
)

RUBOCOP_ARGS=""

while getopts "alh" OPTION; do
case $OPTION in
  a)
    RUBOCOP_ARGS="$RUBOCOP_ARGS -a"
    ;;
  l)
    RUBOCOP_ARGS="$RUBOCOP_ARGS -l"
    ;;
  h)
    echo "$usage"
    exit 0
    ;;
  esac
done

echo "Running rubocop with flags: $RUBOCOP_ARGS"

git status -s | cut -f 3 -d" " | xargs rubocop $RUBOCOP_ARGS
