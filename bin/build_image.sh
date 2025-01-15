#!/usr/bin/env bash

# build the portal Docker image and tag accordingly, then push to GCR
# cleans up untagged images after push when overwriting tags
# meant to be run as part of Jenkins deployment, but can be used as standalone to build/push specified image
# TODO (SCP-4494): Add this script to corresponding Jenkins jobs
THIS_DIR="$(cd "$(dirname -- "$0")"; pwd)"

# common libraries
. $THIS_DIR/bash_utils.sh
. $THIS_DIR/github_releases.sh

usage=$(
cat <<EOF
$0 [OPTION]
-v VALUE  specify version tag for docker image
-g VALUE  provide an alias for the gcloud command (if running via gcloud Docker image, for instance)
-h        print this text
EOF
)

function main {
  # The "broad-singlecellportal-staging" GCR repository is used in production.
  # The "development" tag is used in non-production deployment.  For production deployment, tag is version number for
  # upcoming release, e.g. 1.20.0.
  # More context: https://github.com/broadinstitute/single_cell_portal_core/pull/1552#discussion_r910424433
  # TODO: (SCP-4496): Move production-related GCR images out of staging project

  # Google Artifact Registry (GAR) formats Docker image names differently than the canonical Container Registry format
  # both refer to the same image digest and will work with 'docker pull', but the GCR names do not work with any
  # 'gcloud artifacts docker' commands
  # for example:
  # GCR name: gcr.io/broad-singlecellportal-staging/single-cell-portal
  # GAR name: us-docker.pkg.dev/broad-singlecellportal-staging/gcr.io/single-cell-portal
  VERSION_TAG=$(extract_release_tag "0")
  REPO='gcr.io'
  PROJECT='broad-singlecellportal-staging'
  IMAGE='single-cell-portal'
  GAR_NAME="us-docker.pkg.dev/$PROJECT/$REPO/$IMAGE"
  IMAGE_NAME="$REPO/$PROJECT/$IMAGE"
  GCLOUD_ALIAS='gcloud'
  while getopts "v:g:h" OPTION; do
    case $OPTION in
      v)
        VERSION_TAG="$OPTARG"
        ;;
      h)
        echo "$usage"
        exit 0
        ;;
      g)
        echo "### SUBSTITUTING '$OPTARG' FOR $GCLOUD_ALIAS ###"
        GCLOUD_ALIAS=("$OPTARG")
        ;;
      *)
        echo "unrecognized option"
        echo "$usage"
        exit 1
        ;;
    esac
  done

  # skip building a tagged release if it already exists, unless this is the development branch
  EXISTING_DIGEST=$($GCLOUD_ALIAS artifacts docker images list $GAR_NAME --include-tags --filter="tags=$VERSION_TAG" --format='get(version)')
  if [[ "$VERSION_TAG" != 'development' ]] && [[ -n "$EXISTING_DIGEST" ]]; then
    exit_with_error_message "unable to build $VERSION_TAG as it already exists with digest $EXISTING_DIGEST"
  fi

  # build requested image
  echo "*** BUILDING IMAGE REF $IMAGE_NAME:$VERSION_TAG ***"
  docker build -t $IMAGE_NAME:$VERSION_TAG . || exit_with_error_message "could not build docker image"
  echo "*** BUILD COMPLETE, PUSHING $IMAGE_NAME:$VERSION_TAG ***"
  docker push $IMAGE_NAME:$VERSION_TAG || exit_with_error_message "could not push docker image $IMAGE_NAME:$VERSION_TAG"
  echo "*** PUSH COMPLETE ***"
  # pushing an image with the same tag as an existing one (which will happen each time with 'development') can leave
  # behind an untagged image that needs to be deleted - these can be found with --filter='-tags:*'
  UNTAGGED=$($GCLOUD_ALIAS artifacts docker images list $GAR_NAME --include-tags --filter="-tags:*" --format="get(version)")
  if [[ -n "$UNTAGGED" ]]; then
    echo "*** DELETING UNTAGGED IMAGE DIGEST $UNTAGGED ***"
    $GCLOUD_ALIAS artifacts docker images delete $GAR_NAME@$UNTAGGED --quiet || exit_with_error_message "could not delete image $UNTAGGED"
    echo "*** UNTAGGED IMAGE $UNTAGGED SUCCESSFULLY DELETED ***"
  fi
}

main "$@"
