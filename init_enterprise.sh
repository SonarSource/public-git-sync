#!/bin/bash

##############################################################################################
##
## This script is intended to be run on a clone of repository SonarSource/sonar-enterprise.
##
## This script set the initial tags on branches "master" and "public_master" on which
## script update_public_master.sh will rely on to work.
##
## This script will detect and fail if tags are already present.
##
##############################################################################################


set -euo pipefail

function info() {
  local MESSAGE="$1"
  echo "[INFO] ${MESSAGE}"
}

function error() {
  local MESSAGE="$1"
  echo "[ERROR] ${MESSAGE}"
}

REMOTE="origin"
SQ_REMOTE="sq"
REF_TREE_ROOT="refs/public_sync"
# in branch master_public, created from SonarSource/sonarqube master
PUBLIC_SQ_HEAD_SHA1="73e39a73e70b97ab0043cf5abc4eddcf68f2ce00"
# in branch master
SQ_MERGE_COMMIT_SHA1="b4eeaaa8b52bf9a51c2e4bf18436831ccb389146"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# to know where we are
git checkout master

info "Syncing refs from remote..."
git fetch "${REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

info "Creating SQ remote..."
if ! $(git remote | grep -qxF "${SQ_REMOTE}"); then
  git remote add "${SQ_REMOTE}" "git@github.com:SonarSource/sonarqube.git"
fi

# create "pulic_master" if doesn't exist yet
if [ "$(git branch --list "public_master")" = "" ]; then
  info "create branch public_master from ${PUBLIC_SQ_HEAD_SHA1}"
  git checkout -b "public_master" "${PUBLIC_SQ_HEAD_SHA1}"
fi

# fail if already initialized
if [ "$(git for-each-ref --count=1 "${REF_TREE_ROOT}")" != "" ]; then
  error "References already initialized. See values below:"
  git for-each-ref "${REF_TREE_ROOT}"
  exit 1
fi

info "create inital refs"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/master" "${SQ_MERGE_COMMIT_SHA1}"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/public_master" "${PUBLIC_SQ_HEAD_SHA1}"

info "done"

