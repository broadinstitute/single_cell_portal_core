#!/usr/bin/env bash

THIS_DIR="$(cd "$(dirname -- "$0")"; pwd)"

# common libraries
. $THIS_DIR/bash_utils.sh
. $THIS_DIR/docker_utils.sh

# runs deployment on a remote host (different from deploy.sh which runs on a Jenkins node)

function main {
    # make sure that all necessary variables have been set
    PORTAL_CONTAINER="single_cell"
    VERSION_TAG="development"
    echo "### USER: $(whoami) ###"

    while getopts "v:" OPTION; do
      case $OPTION in
        v)
          VERSION_TAG="$OPTARG"
          ;;
      esac
    done

    if [[ -z "$PORTAL_SECRETS_PATH" ]] || [[ -z "$DESTINATION_BASE_DIR" ]]; then
        exit_with_error_message "Not all necessary variables have been set: Git branch: $GIT_BRANCH; " \
            "secrets: $PORTAL_SECRETS_PATH; base directory: $DESTINATION_BASE_DIR"
    fi

    # pull docker image to reduce downtime
    # The "broad-singlecellportal-staging" GCR repository is used in production.
    # The "development" tag is used in non-production deployment.  For production deployment, tag is version number for
    # upcoming release, e.g. 1.20.0.
    # More context: https://github.com/broadinstitute/single_cell_portal_core/pull/1552#discussion_r910424433
    # TODO: (SCP-4496): Move production-related GCR images out of staging project
    DOCKER_IMAGE_NAME='gcr.io/broad-singlecellportal-staging/single-cell-portal'
    docker pull $DOCKER_IMAGE_NAME:$VERSION_TAG || exit_with_error_message "Cannot pull requested image $DOCKER_IMAGE_NAME:$VERSION_TAG"

    # stop docker container and remove it
    if [[ $(ensure_container_running $PORTAL_CONTAINER) = "0" ]]; then
        echo "### Stopping running container $PORTAL_CONTAINER ###"
        stop_docker_container $PORTAL_CONTAINER || exit_with_error_message "Cannot stop docker container $PORTAL_CONTAINER"
    fi
    for container in $(get_all_containers); do
       if [[ "$container" = "$PORTAL_CONTAINER" ]]; then
           echo "### Removing docker container $PORTAL_CONTAINER ... ###"
           remove_docker_container $PORTAL_CONTAINER || exit_with_error_message "Cannot remove docker container $PORTAL_CONTAINER"
       fi
    done
    echo "### COMPLETED ###"

    # load env secrets from file, then clean up
    echo "### loading env secrets ###"
    . $PORTAL_SECRETS_PATH
    echo "### COMPLETED ###"

    # run boot command
    echo "### Booting $PORTAL_CONTAINER with Docker image version $VERSION_TAG ###"
    run_command_in_deployment "bin/boot_docker -e $PASSENGER_APP_ENV -d $DESTINATION_BASE_DIR -h $PROD_HOSTNAME -N $PORTAL_NAMESPACE -D $VERSION_TAG -m $MONGO_LOCALHOST"
    echo "### COMPLETED ###"

    # ensure portal is running
    echo "### Ensuring boot ###"
    COUNTER=0
    while [[ $COUNTER -lt 12 ]]; do
        COUNTER=$[$COUNTER + 1]
        echo "portal not running on attempt $COUNTER, waiting 5 seconds..."
        sleep 5
        if [[ $(ensure_container_running $PORTAL_CONTAINER) = "0" ]]; then break 2; fi
    done
    if [[ $(ensure_container_running $PORTAL_CONTAINER) = "1" ]] ; then exit_with_error_message "Portal still not running after 1 minute, deployment failed" ; fi
    echo "### COMPLETED ###"

    PORTAL_HOMEPAGE="https://$PROD_HOSTNAME/single_cell"
    echo "### ENSURING PORTAL IS AVAILABLE AT $PORTAL_HOMEPAGE ###"
    HOMEPAGE_COUNTER=0
    HTTP_STATUS=$(get_http_status_code $PORTAL_HOMEPAGE)
    while [[ $HOMEPAGE_COUNTER -lt 24 ]]; do
        if [[ "$HTTP_STATUS" = "200" ]]; then
          echo "DEBUG: hooray, got a 200 back from $PORTAL_HOMEPAGE"
          break 2;
        else
          HOMEPAGE_COUNTER=$[$HOMEPAGE_COUNTER + 1]
          echo "home page not available on attempt $HOMEPAGE_COUNTER, waiting 15 seconds..."
          sleep 15
          HTTP_STATUS=$(get_http_status_code $PORTAL_HOMEPAGE)
        fi
    done
    if [[ "$HTTP_STATUS" = "200" ]] ; then
      exit_with_error_message "Portal unavailable at $PORTAL_HOMEPAGE after 6 minutes with HTTP status: $HTTP_STATUS"
    fi
    echo "### CLEANING UP SECRETS/OLD IMAGES ###"
    rm $PORTAL_SECRETS_PATH
    prune_docker_artifacts "$DOCKER_IMAGE_NAME" "$VERSION_TAG"
    echo "### DEPLOYMENT COMPLETED ###"
}

function run_command_in_deployment {
    COMMAND="$1"
    cd $DESTINATION_BASE_DIR ; $COMMAND
}

# make a HEAD request on URL and return HTTP status code
function get_http_status_code {
    URL="$1"
    echo $(curl -Isk $URL | head -n 1 | awk '{ print $2 }')
}


main "$@"
