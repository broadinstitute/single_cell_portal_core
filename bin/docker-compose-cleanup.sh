#! /bin/sh

# docker-compose-cleanup.sh
# stop/remove all containers/volumes created by docker-compose and revert environment config files
# More context: https://github.com/broadinstitute/single_cell_portal_core#hybrid-docker-local-development

# suppress '"GCR_IMAGE" variable is not set' warning, actual image/tag are irrelevant here
export GCR_IMAGE="gcr.io/broad-singlecellportal-staging/single-cell-portal:development"
echo "### REMOVING CONTAINERS/VOLUMES ###"
# set VITE_FRONTEND_SERVICE_WORKER_CACHE to silence warnings from docker-compose
VITE_FRONTEND_SERVICE_WORKER_CACHE="$VITE_FRONTEND_SERVICE_WORKER_CACHE" \
docker-compose -f docker-compose-dev.yaml down
docker volume prune --force
rm tmp/pids/*.pid
echo "### REVERTING ENVIRONMENT ###"
./rails_local_setup.rb
