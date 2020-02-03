#!/usr/bin/env bash

# extract secrets from vault, copy to remote host, and launch boot script for deployment

THIS_DIR="$(cd "$(dirname "$0")"; pwd)"

# common libraries
. $THIS_DIR/bash_utils.sh
. $THIS_DIR/extract_vault_secrets.sh

function main {

    # defaults
    SSH_USER="docker-user"
    DESTINATION_BASE_DIR='/home/docker-user/deployments/single_cell_portal_core'
    GIT_BRANCH="master"
    PASSENGER_APP_ENV="production"
    BOOT_COMMAND="bin/remote_deploy.sh"

    while getopts "p:s:r:e:b:d:h:S:H" OPTION; do
        case $OPTION in
            p)
                PORTAL_SECRETS_VAULT_PATH="$OPTARG"
                ;;
            s)
                SERVICE_ACCOUNT_VAULT_PATH="$OPTARG"
                ;;
            r)
                READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH="$OPTARG"
                ;;
            e)
                PASSENGER_APP_ENV="$OPTARG"
                ;;
            b)
                GIT_BRANCH="$OPTARG"
                ;;
            d)
                DESTINATION_BASE_DIR="$OPTARG"
                ;;
            h)
                DESTINATION_HOST="$OPTARG"
                ;;
            S)
                SSH_KEYFILE="$OPTARG"
                ;;
            H)
                echo "$usage"
                exit 0
                ;;
            *)
                echo "unrecognized option"
                echo "$usage"
                exit 1
                ;;
        esac
    done

    # construct SSH command
    SSH_OPTS="-o CheckHostIP=no -o StrictHostKeyChecking=no"
    if [[ -n $SSH_KEYFILE ]]; then
        SSH_OPTS=$SSH_OPTS" -i $SSH_KEYFILE"
    fi
    SSH_COMMAND="ssh $SSH_OPTS $SSH_USER@$DESTINATION_HOST"

    # exit if all config is not present
    if [[ -z "$PORTAL_SECRETS_VAULT_PATH" ]] || [[ -z "$SERVICE_ACCOUNT_VAULT_PATH" ]] || [[ -z "$READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH" ]]; then
        exit_with_error_message "Did not supply all necessary parameters: portal config: '$PORTAL_SECRETS_VAULT_PATH';" \
            "service account path: '$SERVICE_ACCOUNT_VAULT_PATH'; read-only service account path: '$READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH'$newline$newline$usage"
    fi

    echo "### extracting secrets from vault ###"
    CONFIG_FILENAME="$(set_export_filename $PORTAL_SECRETS_VAULT_PATH env)"
    SERVICE_ACCOUNT_FILENAME="$(set_export_filename $SERVICE_ACCOUNT_VAULT_PATH)"
    READ_ONLY_SERVICE_ACCOUNT_FILENAME="$(set_export_filename $READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH)"
    extract_vault_secrets_as_env_file "$PORTAL_SECRETS_VAULT_PATH"
    extract_service_account_credentials "$SERVICE_ACCOUNT_VAULT_PATH"
    extract_service_account_credentials "$READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH"
    PORTAL_SECRETS_PATH="$DESTINATION_BASE_DIR/config/$CONFIG_FILENAME"
    SERVICE_ACCOUNT_JSON_PATH="$DESTINATION_BASE_DIR/config/$SERVICE_ACCOUNT_FILENAME"
    READ_ONLY_SERVICE_ACCOUNT_JSON_PATH="$DESTINATION_BASE_DIR/config/$READ_ONLY_SERVICE_ACCOUNT_FILENAME"
    echo "### COMPLETED ###"

    # set paths in env file to be correct inside container
    echo "### Exporting Service Account Keys: $SERVICE_ACCOUNT_JSON_PATH, $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH ###"
    echo "export SERVICE_ACCOUNT_KEY=/home/app/webapp/config/$SERVICE_ACCOUNT_FILENAME" >> $CONFIG_FILENAME
    echo "export READ_ONLY_SERVICE_ACCOUNT_KEY=/home/app/webapp/config/$READ_ONLY_SERVICE_ACCOUNT_FILENAME" >> $CONFIG_FILENAME
    echo "### COMPLETED ###"

    # move secrets to remote host
    echo "### migrating secrets to remote host ###"
    copy_file_to_remote ./$CONFIG_FILENAME $PORTAL_SECRETS_PATH || exit_with_error_message "could not move $CONFIG_FILENAME to $PORTAL_SECRETS_PATH"
    copy_file_to_remote ./$SERVICE_ACCOUNT_FILENAME $SERVICE_ACCOUNT_JSON_PATH || exit_with_error_message "could not move $SERVICE_ACCOUNT_FILENAME to $SERVICE_ACCOUNT_JSON_PATH"
    copy_file_to_remote ./$READ_ONLY_SERVICE_ACCOUNT_FILENAME $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH || exit_with_error_message "could not move $READ_ONLY_SERVICE_ACCOUNT_FILENAME to $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH"
    echo "### COMPLETED ###"

    # update source on remote host to pull in changes before deployment
    echo "### pulling updated source from git on branch $GIT_BRANCH ###"
    run_remote_command "git fetch" || exit_with_error_message "could not checkout $GIT_BRANCH"
    run_remote_command "git checkout yarn.lock" || exit_with_error_message "could not reset yarn.lock file"
    run_remote_command "git checkout $GIT_BRANCH && git pull" || exit_with_error_message "could not checkout $GIT_BRANCH"
    echo "### COMPLETED ###"

    echo "### running remote deploy script ###"
    run_remote_command "$(set_remote_environment_vars) $BOOT_COMMAND" || exit_with_error_message "could not run $(set_remote_environment_vars) $BOOT_COMMAND on $DESTINATION_HOST:$DESTINATION_BASE_DIR"
    echo "### COMPLETED ###"
}

# TODO: Although I made minimum changes to clarify required vs optional parameters, this may now need rewording...
usage=$(
cat <<EOF
USAGE:
   $(basename $0) <required parameters> [<options>]

### extract secrets from vault, copy to remote host, build/stop/remove docker container and launch boot script for deployment ###

[REQUIRED PARAMETERS]
-p VALUE	set the path to configuration secrets in vault
-s VALUE	set the path to the main service account json in vault
-r VALUE	set the path to the read-only service account json in vault

[OPTIONS]
-e VALUE	set the environment to boot the portal in
-b VALUE	set the branch to pull from git (defaults to master)
-d VALUE	set the target directory to deploy from (defaults to $DESTINATION_BASE_DIR)
-S VALUE	set the path to SSH_KEYFILE (private key for SSH auth, no default, not needing except for manual testing)
-h VALUE	set the DESTINATION_HOST (remote GCP VM to SSH into, no default)
-H COMMAND	print this text
EOF
)

function run_remote_command {
    REMOTE_COMMAND="$1"
    $SSH_COMMAND "cd $DESTINATION_BASE_DIR ; $REMOTE_COMMAND"
}

function copy_file_to_remote {
    LOCAL_FILEPATH="$1"
    REMOTE_FILEPATH="$2"
    cat $LOCAL_FILEPATH | $SSH_COMMAND "cat > $REMOTE_FILEPATH"
}

function set_remote_environment_vars {
    echo "PASSENGER_APP_ENV='$PASSENGER_APP_ENV' PORTAL_SECRETS_PATH='$PORTAL_SECRETS_PATH' DESTINATION_BASE_DIR='$DESTINATION_BASE_DIR'"
}

main "$@"
