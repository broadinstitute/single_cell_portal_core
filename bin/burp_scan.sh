#!/usr/bin/env bash

set -eu

# Burp private Docker image URL (this assumes the client was already
# authenticated with container registry using burp_start.sh)
IMAGE="$1"

# Scan collected traffic and report results (optional)
docker run --rm -it --net host --entrypoint /automation/BroadBurpScanner.py "${IMAGE}" \
  http://localhost --action scan
