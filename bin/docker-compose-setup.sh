#! /bin/sh

# docker-compose-setup.sh
# bring up local development environment via docker-compose
# More context: https://github.com/broadinstitute/single_cell_portal_core#hybrid-docker-local-development

usage=$(
cat <<EOF
$0 [OPTION]
-d   run docker-compose in detached mode (default is attatched to terminal STDOUT)
-c   enable VITE_FRONTEND_SERVICE_WORKER_CACHE (default is disabled)
-i IMAGE_TAG   override default GCR image tag of development
-h   print this text
EOF
)

DETACHED=""
VITE_FRONTEND_SERVICE_WORKER_CACHE="false"
IMAGE_TAG="development"
while getopts "dchi:" OPTION; do
case $OPTION in
  d)
    echo "### SETTING DETACHED ###"
    DETACHED="--detach"
    echo "### PLEASE ALLOW 30s ONCE SERVICES START BEFORE ISSUING REQUESTS ###"
    ;;
  c)
    echo "### ENABLING VITE_FRONTEND_SERVICE_WORKER_CACHE ###"
    VITE_FRONTEND_SERVICE_WORKER_CACHE="true"
    ;;
  h)
    echo "$usage"
    exit 0
    ;;
  i)
    echo "### SETTING GCR IMAGE TAG TO $OPTARG ###"
    IMAGE_TAG="$OPTARG"
    ;;
  *)
    echo "unrecognized option"
    echo "$usage"
    exit 1
    ;;
  esac
done
export GCR_IMAGE="gcr.io/broad-singlecellportal-staging/single-cell-portal:$IMAGE_TAG"
echo "### SETTING UP ENVIRONMENT ###"
./rails_local_setup.rb --docker-paths
source config/secrets/.source_env.bash
rm tmp/pids/*.pid
# determine if there are upstream changes that would require a rebuild of the Docker image
LOCAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
CHANGED=$(git diff "$LOCAL_BRANCH" development --name-only -- Dockerfile)
if [[ "$CHANGED" = "Dockerfile" ]]; then
  echo "### DOCKERFILE CHANGES DETECTED, BUILDING $GCR_IMAGE LOCALLY ###"
  docker build -t "$GCR_IMAGE" .
else
  echo "### PULLING UPDATED IMAGE FOR $GCR_IMAGE ###"
  docker pull "$GCR_IMAGE"
fi
echo "### STARTING SERVICES ###"
VITE_FRONTEND_SERVICE_WORKER_CACHE="$VITE_FRONTEND_SERVICE_WORKER_CACHE" \
docker-compose -f docker-compose-dev.yaml up $DETACHED
