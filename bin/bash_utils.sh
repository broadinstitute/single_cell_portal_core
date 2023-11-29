#!/usr/bin/env bash

# common functions to share amongst different bash scripts for running/deploying SCP docker container

# https://stackoverflow.com/a/56841815/1735179
export newline='
'

# exit 1 with an error message
function exit_with_error_message {
    echo "ERROR: $@" >&2;
    exit 1
}

function set_pathname_extension {
    FULL_PATH="$1"
    SEP="."
    echo ${FULL_PATH##*$SEP} || exit_with_error_message "could not extract file extension from $FULL_PATH"
}

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
