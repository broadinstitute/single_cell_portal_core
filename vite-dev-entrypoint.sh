#! /bin/sh

# set SCP_VERSION to current branch name + short commit SHA
# e.g. my-feature-branch:f4e377a60
SCP_VERSION="$(git branch --show-current):$(git rev-parse --short HEAD)"

yarn install
SCP_VERSION="\"$SCP_VERSION\"" bin/vite dev
