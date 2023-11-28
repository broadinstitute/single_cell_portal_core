#!/usr/bin/env bash

# load secrets from Vault for running/deploying SCP docker container

# defaults
THIS_DIR="$(cd "$(dirname -- "$0")"; pwd)"

# load common utils
. $THIS_DIR/bash_utils.sh

# extract filename from end of vault path, replacing with new extension if needed
function set_export_filename {
    SECRET_PATH="$1"
    REQUESTED_EXTENSION="$2"
    FILENAME=$(basename $SECRET_PATH)
    if [[ -n "$REQUESTED_EXTENSION" ]]; then
        # replace existing extension with requested extension (like .env for non-JSON secrets)
        EXPORT_EXTENSION="$(set_pathname_extension $FILENAME)"
        FILENAME="${FILENAME//$EXPORT_EXTENSION/$REQUESTED_EXTENSION}" || exit_with_error_message "could not change export filename extension to $REQUESTED_EXTENSION from $EXPORT_EXTENSION"
    fi
    echo "$FILENAME"
}
