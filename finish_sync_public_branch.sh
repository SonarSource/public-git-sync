#!/bin/bash
#
# This script should only be called from sync_public_branch.sh,
# or after recovering from a cherry-picking failure of sync_public_branch.sh,
# to complete the sync manually.
#
# parameters:
# BRANCH: master, branch-7.9, ...
#

set -euo pipefail

REF_TREE_ROOT="refs/public_sync"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
BRANCH="${1}"
WORK_BRANCH="${BRANCH}_work"
PUBLIC_BRANCH="public_${BRANCH}"
PUBLIC_WORK_BRANCH="public_${BRANCH}_work"

info() {
  local message="$1"
  echo "[INFO] ${message}"
}

error() {
  local message="$1"
  echo 
  echo "[ERROR] ${message}"
}

pause() {
  echo "pause..."
#  read
}

latest_ref() {
  local pattern="$1"
  git for-each-ref --count=1 --sort=-refname "$pattern" --format='%(refname)'
}

# Verify that two refs are "public-equivalent": only have differences in private/
validate_public_equivalent_refs() {
  if git diff --name-only "$1" "$2" | grep -v "^private/" >/dev/null; then
    error "Illegal state: '$1' and '$2' should only differ in private/"
    info "Investigate the output of: git diff --name-only $1 $2"
    exit 1
  fi
}


info "Reading references..."
LATEST_PUBLIC_BRANCH_REF="$(latest_ref "${REF_TREE_ROOT}/*/${PUBLIC_BRANCH}")"

info "Clearing any empty commit in ${WORK_BRANCH}..."
pause
git filter-branch -f --prune-empty ${LATEST_PUBLIC_BRANCH_REF}..HEAD

# merge ${PUBLIC_WORK_BRANCH} into ${PUBLIC_BRANCH} (ff-only for safety)
info "update ${PUBLIC_BRANCH}"
pause
git checkout "${PUBLIC_BRANCH}"
git merge --ff-only "${PUBLIC_WORK_BRANCH}"

validate_public_equivalent_refs "${PUBLIC_BRANCH}" "${BRANCH}"

info "create refs"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/${BRANCH}" "${BRANCH}"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/${PUBLIC_BRANCH}" "${PUBLIC_BRANCH}"

# log created references
git for-each-ref --count=2 --sort=-refname "${REF_TREE_ROOT}"

info "done"
