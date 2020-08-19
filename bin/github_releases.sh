#!/usr/bin/env bash

# functions for retrieving GitHub releases for SCP and extracting requested release tag names
# by walking back through release history
#
# Requirements: curl, jq

REPO_URL='https://api.github.com/repos/broadinstitute/single_cell_portal_core/releases'

# Get all GitHub published releases for $REPO_URL
function get_all_releases {
  echo $(curl -X GET --header 'application/json' --silent $REPO_URL)
}

# extract a release tag name from a GitHub release JSON object
# will default targeting the previous release from the most recent
function extract_release_tag {
  OFFSET="$1"
  if [[ -z "$OFFSET" ]]; then
    OFFSET="1"
  fi
  echo $(get_all_releases | jq ".[$OFFSET].tag_name" | sed 's/"//g')
}
