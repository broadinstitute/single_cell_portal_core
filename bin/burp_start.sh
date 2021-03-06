#!/usr/bin/env bash

set -eu

# Burp private Docker image URL
IMAGE="$1"

# Base64-encoded Service Account Key JSON to pull the image from container registry
BASE64_KEY="$2"

# Authenticate with container registry
REGISTRY=$(echo "${IMAGE}" | awk -F/ '{print $1}')
echo "${BASE64_KEY}" | docker login -u _json_key_base64 --password-stdin "https://${REGISTRY}"

# Start Burp container in the background
CONTAINER="burp"
docker run --rm -d --net host --name "${CONTAINER}" "${IMAGE}"

# Wait until startup
( docker logs "${CONTAINER}" -f & ) | grep -q "Started BurpApplication"
