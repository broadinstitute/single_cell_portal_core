#! /bin/sh

# docker-compose-setup.sh
# bring up local development environment via docker-compose
# More context: https://github.com/broadinstitute/single_cell_portal_core#hybrid-docker-local-development

usage=$(
cat <<EOF
$0 [OPTION]
-d  run docker-compose in detached mode (default is attatched to terminal STDOUT)
-c  enable VITE_FRONTEND_SERVICE_WORKER_CACHE (default is disabled)
-i  {IMAGE_TAG}  override default GCR image tag of development
-p  {PORTAL_RAM_GB}  specify as integer the amount of RAM in GB for the single_cell container
-v  {VITE_RAM_GB}  specify as integer the amount of RAM in GB for the single_cell_vite container
-l  use a local copy of GCR_IMAGE (for testing build updates)
-h  print this text
EOF
)

DETACHED=""
VITE_FRONTEND_SERVICE_WORKER_CACHE="false"
IMAGE_TAG="development"
LOCAL="false"
export PORTAL_RAM_GB="6"
export VITE_RAM_GB="2"
while getopts "dchi:p:v:l" OPTION; do
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
  p)
    echo "### SETTING PORTAL_RAM_GB TO $OPTARG ###"
    PORTAL_RAM_GB="$OPTARG"
    ;;
  v)
    echo "### SETTING VITE_RAM_GB TO $OPTARG ###"
    VITE_RAM_GB="$OPTARG"
    ;;
  l)
    LOCAL="true"
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
elif [[ "$LOCAL" = "false" ]]; then
  echo "### PULLING UPDATED IMAGE FOR $GCR_IMAGE ###"
  docker pull "$GCR_IMAGE"
else
  echo "### USING LOCAL COPY OF $GCR_IMAGE ###"
fi
echo "### STARTING SERVICES ###"
VITE_FRONTEND_SERVICE_WORKER_CACHE="$VITE_FRONTEND_SERVICE_WORKER_CACHE" \
docker-compose -f docker-compose-dev.yaml up $DETACHED
