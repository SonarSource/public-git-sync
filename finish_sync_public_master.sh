#!/bin/bash
#
# This script should only be called from sync_public_master.sh,
# or after recovering from a cherry-picking failure of sync_public_master.sh,
# to complete the sync manually.
#

set -euo pipefail

info() {
  local MESSAGE="$1"
  echo "[INFO] ${MESSAGE}"
}

error() {
  local MESSAGE="$1"
  echo 
  echo "[ERROR] ${MESSAGE}"
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

REF_TREE_ROOT="refs/public_sync"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

info "Reading references..."
LATEST_PUBLIC_MASTER_REF="$(latest_ref "${REF_TREE_ROOT}/*/public_master")"

info "Clearing any empty commit in master_work..."
pause
git filter-branch -f --prune-empty ${LATEST_PUBLIC_MASTER_REF}..HEAD

# merge public_master_work into public_master (ff-only for safety)
info "update public_master"
pause
git checkout "public_master"
git merge --ff-only "public_master_work"

validate_public_equivalent_refs "public_master" "master"

info "create refs"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/master" "master"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/public_master" "public_master"

# log created references
git for-each-ref --count=2 --sort=-refname "${REF_TREE_ROOT}"

info "done"
