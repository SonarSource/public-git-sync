#!/bin/bash

##############################################################################################
##
## This script is intended to be run on a clone of repository SonarSource/sonar-enterprise 
## or slang-enterprise
##
## This script set the initial tags on branches "master" and "public_master" on which
## script update_public_master.sh will rely on to work.
##
## This script will detect and fail if tags are already present.
##
## parameters: 
## PUBLIC_REMOTE: slang or sq
## PUBLIC_REMOTE_URL: git@github.com:SonarSource/slang.git or git@github.com:SonarSource/sonarqube.git
## BRANCH: master, branch-7.9, ...
##
##############################################################################################


set -euo pipefail

info() {
  local message="$1"
  echo "[INFO] ${message}"
}

error() {
  local message="$1"
  echo "[ERROR] ${message}"
}

PRIVATE_REMOTE="origin"
PUBLIC_REMOTE="${1}"
PUBLIC_REMOTE_URL="${2}"
BRANCH="${3}"
PUBLIC_BRANCH="public_${BRANCH}"
REF_TREE_ROOT="refs/public_sync"
# in branch master_public, created from SonarSource/slang master
PUBLIC_PROJECT_HEAD_SHA1="88b6f0111c4bfdb243b9beaa531a6c7a49ac30b0"
# in branch master
PROJECT_MERGE_COMMIT_SHA1="d169e263121b02a1332e8936793705820c7a10d3"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

info "Initializing branch ${BRANCH} for remote ${PUBLIC_REMOTE} from repository ${PUBLIC_REMOTE_URL}..."

# to know where we are
git checkout "${BRANCH}"

info "Syncing refs from remote..."
git fetch "${PRIVATE_REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

info "Creating SQ remote..."
if ! git remote | grep -qxF "${PUBLIC_REMOTE}"; then
  git remote add "${PUBLIC_REMOTE}" "${PUBLIC_REMOTE_URL}"
fi

# create "${PUBLIC_BRANCH}" if doesn't exist yet
if [ -z "$(git branch --list "${PUBLIC_BRANCH}")" ]; then
  info "create branch "${PUBLIC_BRANCH}" from ${PUBLIC_PROJECT_HEAD_SHA1}"
  git checkout -b "${PUBLIC_BRANCH}" "${PUBLIC_PROJECT_HEAD_SHA1}"
fi

# fail if already initialized
if [ "$(git for-each-ref --count=1 "${REF_TREE_ROOT}")" ]; then
  error "References already initialized. See values below:"
  git for-each-ref "${REF_TREE_ROOT}"
  exit 1
fi

info "create inital refs"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/${BRANCH}" "${PROJECT_MERGE_COMMIT_SHA1}"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/${PUBLIC_BRANCH}" "${PUBLIC_PROJECT_HEAD_SHA1}"

info "done"

