#!/usr/bin/env bash

# script that can run deployments to GCE via Github Action runner
# uses gcloud Docker image for authentication & ssh access via service accounts
# vault secrets are extracted using extract-vault-secret-to-file action

THIS_DIR="$(cd "$(dirname -- "$0")"; pwd)"

# common libraries
. $THIS_DIR/bash_utils.sh
. $THIS_DIR/github_releases.sh

function main {
  # defaults
  SSH_USER="jenkins"
  DESTINATION_BASE_DIR='/home/jenkins/deployments/single_cell_portal_core'
  GIT_BRANCH="master"
  PASSENGER_APP_ENV="production"
  BOOT_COMMAND="bin/remote_deploy.sh"
  SCP_REPO="https://github.com/broadinstitute/single_cell_portal_core.git"
  ROLLBACK="false"
  HOTFIX="false"
  TAG_OFFSET=1
  VERSION_TAG="development"
  GCLOUD_DOCKER_IMAGE="gcr.io/google.com/cloudsdktool/google-cloud-cli:latest"
  GOOGLE_PROJECT="broad-singlecellportal"
  COMPUTE_ZONE="us-central1-a"
  GCLOUD_CONFIG_IMAGE="gcloud-config"

  while getopts "p:s:r:e:b:d:h:S:u:H:t:Rfv:g:z:G:" OPTION; do
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
      u)
        SSH_USER="$OPTARG"
        ;;
      R)
        ROLLBACK="true"
        ;;
      f)
        HOTFIX="true"
        ;;
      t)
        TAG_OFFSET="$OPTARG"
        ;;
      v)
        VERSION_TAG="$OPTARG"
        ;;
      g)
        GOOGLE_PROJECT="$OPTARG"
        ;;
      z)
        COMPUTE_ZONE="$OPTARG"
        ;;
      G)
        GCLOUD_CONFIG_IMAGE="$OPTARG"
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

  echo "DEBUG: $(ls -la)"

  # construct SSH command using gcloud and Identity Aware Proxy to access VM via authenticated Docker container
  BASE_SSH="docker run --rm $GCLOUD_CONFIG_IMAGE gcloud compute ssh"
  SSH_ARGS="$SSH_USER@$DESTINATION_HOST --tunnel-through-iap --project $GOOGLE_PROJECT --zone $COMPUTE_ZONE"
  SSH_COMMAND="$BASE_SSH  $SSH_ARGS --verbosity error --command "

  # copy command using gcloud compute scp
  BASE_COPY="docker run --rm $GCLOUD_CONFIG_IMAGE gcloud compute scp"
  COPY_ARGS=

  # exit if all config is not present
  if [[ -z "$PORTAL_SECRETS_VAULT_PATH" ]] || [[ -z "$SERVICE_ACCOUNT_VAULT_PATH" ]] || [[ -z "$READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH" ]]; then
    exit_with_error_message "Did not supply all necessary parameters: portal config: '$PORTAL_SECRETS_VAULT_PATH';" \
      "service account path: '$SERVICE_ACCOUNT_VAULT_PATH'; read-only service account path: '$READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH'$newline$newline$usage"
  fi

  echo "### extracting secrets from vault ###"
  CONFIG_FILENAME="$(set_export_filename $PORTAL_SECRETS_VAULT_PATH env)"
  SERVICE_ACCOUNT_FILENAME="$(set_export_filename $SERVICE_ACCOUNT_VAULT_PATH)"
  READ_ONLY_SERVICE_ACCOUNT_FILENAME="$(set_export_filename $READ_ONLY_SERVICE_ACCOUNT_VAULT_PATH)"
  # secrets will have already been extracted via extract-vault-secret-to-file
  PORTAL_SECRETS_PATH="$DESTINATION_BASE_DIR/config/$CONFIG_FILENAME"
  SERVICE_ACCOUNT_JSON_PATH="$DESTINATION_BASE_DIR/config/$SERVICE_ACCOUNT_FILENAME"
  READ_ONLY_SERVICE_ACCOUNT_JSON_PATH="$DESTINATION_BASE_DIR/config/$READ_ONLY_SERVICE_ACCOUNT_FILENAME"
  echo "### COMPLETED ###"

  # set paths in env file to be correct inside container
  echo "### Exporting Service Account Keys: $SERVICE_ACCOUNT_JSON_PATH, $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH ###"
  echo "export SERVICE_ACCOUNT_KEY=/home/app/webapp/config/$SERVICE_ACCOUNT_FILENAME" >> $CONFIG_FILENAME
  echo "export READ_ONLY_SERVICE_ACCOUNT_KEY=/home/app/webapp/config/$READ_ONLY_SERVICE_ACCOUNT_FILENAME" >> $CONFIG_FILENAME
  echo "### COMPLETED ###"

  # init folder/repo if this is the first deploy on this host
  $SSH_COMMAND "if [ ! -d $DESTINATION_BASE_DIR ]; then sudo mkdir -p $DESTINATION_BASE_DIR && sudo chown -R $SSH_USER: $DESTINATION_BASE_DIR; fi"
  run_remote_command "if [ ! -d .git ]; then sudo rm -rf ./* && git clone $SCP_REPO .; fi"

  # move secrets to remote host
  echo "### migrating secrets to remote host ###"
  copy_file_to_remote ./$CONFIG_FILENAME $PORTAL_SECRETS_PATH || exit_with_error_message "could not move $CONFIG_FILENAME to $PORTAL_SECRETS_PATH"
  copy_file_to_remote ./$SERVICE_ACCOUNT_FILENAME $SERVICE_ACCOUNT_JSON_PATH || exit_with_error_message "could not move $SERVICE_ACCOUNT_FILENAME to $SERVICE_ACCOUNT_JSON_PATH"
  copy_file_to_remote ./$READ_ONLY_SERVICE_ACCOUNT_FILENAME $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH || exit_with_error_message "could not move $READ_ONLY_SERVICE_ACCOUNT_FILENAME to $READ_ONLY_SERVICE_ACCOUNT_JSON_PATH"
  echo "### COMPLETED ###"

  # update source on remote host to pull in changes before deployment
  echo "### pulling updated source from git on branch $GIT_BRANCH ###"
  run_remote_command "git remote update" || exit_with_error_message "git remote update failed"
  run_remote_command "git fetch --all --tags" || exit_with_error_message "git fetch --all failed"
  run_remote_command "git checkout yarn.lock" || exit_with_error_message "could not reset yarn.lock file"
  run_remote_command "git checkout $GIT_BRANCH && git pull" || exit_with_error_message "could not checkout $GIT_BRANCH"
  echo "### COMPLETED ###"

  # if this is a production deployment (or a hotfix deployment on staging), get the latest tag to pass to remote_deploy
  if [[ $PASSENGER_APP_ENV == "production" ]] || [[ $HOTFIX == "true" ]]; then
    VERSION_TAG=$(extract_release_tag 0)
  fi

  if [[ $ROLLBACK == "true" ]]; then
    # checkout the requested tag (usually current release - 1)
    echo "### ROLLING BACK DEPLOYMENT BY $TAG_OFFSET RELEASE TAG ###"
    echo "### determining requested release rollback tag on $GIT_BRANCH ###"
    ROLLBACK_TAG=$(extract_release_tag $TAG_OFFSET) || exit_with_error_message "could not get rollback tag in $GIT_BRANCH"
    echo "### rolling back release to tag: $ROLLBACK_TAG on $GIT_BRANCH ###"
    run_remote_command "git checkout tags/$ROLLBACK_TAG" || exit_with_error_message "could not checkout tags/$ROLLBACK_TAG on $GIT_BRANCH"
    VERSION_TAG="$ROLLBACK_TAG"
    echo "### COMPLETED ###"
  fi

  # apply version tag to remote boot command
  BOOT_COMMAND="$BOOT_COMMAND -v $VERSION_TAG"

  echo "### running remote deploy script ###"
  echo "BOOT_COMMAND: $(set_remote_environment_vars) $BOOT_COMMAND"
  run_remote_command "$(set_remote_environment_vars) $BOOT_COMMAND" || exit_with_error_message "could not run $(set_remote_environment_vars) $BOOT_COMMAND on $DESTINATION_HOST:$DESTINATION_BASE_DIR"
  echo "### COMPLETED ###"
}

usage=$(
cat <<EOF
USAGE:
  $(basename $0) <required parameters> [<options>]

### extract secrets from vault, copy to remote host, build/stop/remove docker container and launch boot script for deployment ###

[REQUIRED PARAMETERS]
-p VALUE    set the path to configuration secrets in vault
-s VALUE    set the path to the main service account json in vault
-r VALUE    set the path to the read-only service account json in vault

[OPTIONS]
-e VALUE    set the environment to boot the portal in (defaults to production)
-b VALUE    set the branch to pull from git (defaults to master)
-d VALUE    set the target directory to deploy from (defaults to $DESTINATION_BASE_DIR)
-S VALUE    set the path to SSH_KEYFILE (private key for SSH auth, no default, not needing except for manual testing)
-h VALUE    set the DESTINATION_HOST (remote GCP VM to SSH into, no default)
-R          set ROLLBACK to true to revert release to last known good release
-f          set HOTFIX to true to deploy the latest release tag to a non-production host
-t VALUE    set the TAG_OFFSET value for rolling back a release (defaults to 1, meaning release previous to the current)
-v VALUE    set the VERSION_TAG value to control which Docker tag to pull (defaults to development)
-g VALUE    set the GOOGLE_PROJECT value to control which project to access (defaults to production project)
-z VALUE    set the COMPUTE_ZONE value (for accessing VMs, defaults to us-central1)
-G VALUE    set the GCLOUD_CONFIG_IMAGE value (defaults to $GCLOUD_DOCKER_IMAGE)
-H COMMAND  print this text
EOF
)

function run_remote_command {
  REMOTE_COMMAND="$1"
  $SSH_COMMAND "cd $DESTINATION_BASE_DIR ; $REMOTE_COMMAND"
}

function copy_file_to_remote {
  LOCAL_FILEPATH="$1"
  REMOTE_FILEPATH="$2"
  $SSH_COMMAND "mkdir -p \$(dirname $REMOTE_FILEPATH)"
  BASE_COPY="docker run --rm -v $LOCAL_FILEPATH:$LOCAL_FILEPATH:rw $GCLOUD_CONFIG_IMAGE gcloud compute scp "
  COPY_ARGS="$LOCAL_FILEPATH $SSH_USER@$DESTINATION_HOST:$REMOTE_FILEPATH --tunnel-through-iap --project $GOOGLE_PROJECT --zone $COMPUTE_ZONE"
  COPY_CMD="$BASE_COPY $COPY_ARGS"
  $COPY_CMD
}

function set_remote_environment_vars {
  echo "PASSENGER_APP_ENV='$PASSENGER_APP_ENV' PORTAL_SECRETS_PATH='$PORTAL_SECRETS_PATH' DESTINATION_BASE_DIR='$DESTINATION_BASE_DIR'"
}

main "$@"
