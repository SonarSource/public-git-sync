#!/bin/bash


##############################################################################################
##
## This script is intended to be run on a clone of repository SonarSource/sonar-enterprise 
## or slang-enterprise
##
## This script commits work of init_enteprise.sh and sync_public_master.sh by pushing branch
## to remote public_master and references used by sync_public_master.sh.
## parameters: 
## PUBLIC_REMOTE: slang or sq
##
##############################################################################################

set -euo pipefail

info() {
  local MESSAGE="$1"
  echo "[INFO] ${MESSAGE}"
}

error() {
  local MESSAGE="$1"
  echo "[ERROR] ${MESSAGE}"
}

pause() {
  echo "pause..."
  read
}

PUBLIC_REMOTE=$1
PRIVATE_REMOTE="origin"
REF_TREE_ROOT="refs/public_sync"

# to know where we are
git checkout public_master

info "Pushing public_master..."
git push "${PRIVATE_REMOTE}" "public_master:public_master"
git push "${PUBLIC_REMOTE}" "public_master:master"

info "Pushing refs to ${PUBLIC_REMOTE}..."
TMP_EXISTING_REFS_FILE=$(mktemp)
git ls-remote "${PRIVATE_REMOTE}" | cut -f 2 | grep "^${REF_TREE_ROOT}/" > ${TMP_EXISTING_REFS_FILE} || true

for ref in $(git for-each-ref "${REF_TREE_ROOT}" | cut -f 2 | grep -v --file="${TMP_EXISTING_REFS_FILE}"); do
  echo "committing ref $ref"
  git push "${PRIVATE_REMOTE}" "${ref}"
done

info "done"
