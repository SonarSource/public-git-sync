#!/bin/bash


##############################################################################################
##
## This script is intended to be run on a clone of repository SonarSource/sonar-enterprise.
## This script requires that script init_enteprise.sh has been run prior to being called.
##
## This script updates branch "public_master" with latest changes in "master" which
## apply only to public content.
##
## Branch "public_master" can then merged fast-forward only into branch "master" of
## repository SonarSource/sonarqube.
##
##
##############################################################################################

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

recreate_and_checkout() {
  local BRANCH="$1"
  local NEW_HEAD="$2"

  info "refresh ${BRANCH} to ${NEW_HEAD}"
  if [ "$(git branch --list "${BRANCH}")" ]; then
    git branch -D "${BRANCH}"
  fi
  # "--no-track" to not set upstream to avoid any push to the wrong remote by forcing push command to specify remote
  git checkout --no-track -b "${BRANCH}" "${NEW_HEAD}"
}

latest_ref() {
  local pattern="$1"
  git for-each-ref --count=1 --sort=-refname "$pattern" --format='%(refname)'
}

sync_date() {
  local ref="$1"
  cut -d/ -f3 <<< "$ref"
}

sha1() {
  git rev-parse "$1"
}

same_refs() {
  [ "$(sha1 "$1")" = "$(sha1 "$2")" ]
}

commit() {
  git log -n 1 --pretty="%h - %s (%an %cr)" "$1"
}

REF_TREE_ROOT="refs/public_sync"
REMOTE="origin"
SQ_REMOTE="sq"
SQ_REMOTE_URL="git@github.com:SonarSource/sonarqube.git"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

info "Fetching branches and refs from remote ${REMOTE}..."
git fetch --no-tags "${REMOTE}"
git fetch --no-tags "${REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

info "Ensuring master is up to date..."
git checkout "master" && git pull "${REMOTE}" "master"

if ! git remote | grep -qxF "${SQ_REMOTE}"; then
  info "Creating remote ${SQ_REMOTE}..."
  git remote add "${SQ_REMOTE}" "${SQ_REMOTE_URL}"
fi

info "Fetching branches from remote ${SQ_REMOTE}..."
git fetch --no-tags "${SQ_REMOTE}"

# ensure we have an up to date local branch public_master of ${SQ_REMOTE}/master
recreate_and_checkout "public_master" "${SQ_REMOTE}/master"

info "Reading references..."
LATEST_PUBLIC_MASTER_REF="$(latest_ref "${REF_TREE_ROOT}/*/public_master")"
LATEST_MASTER_REF="$(latest_ref "${REF_TREE_ROOT}/*/master")"
LATEST_PUBLIC_MASTER_SYNC_DATE=$(sync_date "${LATEST_PUBLIC_MASTER_REF}")
LATEST_MASTER_SYNC_DATE=$(sync_date "${LATEST_MASTER_REF}")

if [ "${LATEST_PUBLIC_MASTER_SYNC_DATE}" != "${LATEST_MASTER_SYNC_DATE}" ]; then
  error "Sync date of master (${LATEST_MASTER_SYNC_DATE}) and public_master (${LATEST_PUBLIC_MASTER_SYNC_DATE}) are not consistent. Cannot proceed."
  exit 1
fi

info "Latest sync merged \"$(commit "${LATEST_MASTER_REF}")\" into branch public_master as \"$(commit "${LATEST_PUBLIC_MASTER_REF}")\" with timestamp \"${LATEST_MASTER_SYNC_DATE}\""

if ! same_refs "public_master" "${LATEST_PUBLIC_MASTER_REF}"; then
  error "Latest reference to public master ($(sha1 "${LATEST_PUBLIC_MASTER_REF}")) is not HEAD of branch public_master. Previous run of synchonization script left an inconsistent state"
  exit 1
fi

if same_refs "master" "${LATEST_MASTER_REF}"; then
  info "no new commit to merge"
  exit 0
fi

info "Synchronizing \"$(commit "master")\" into branch public_master..."

# (re)create master_work
recreate_and_checkout "master_work" "master"

# remove private repo data since LATEST_MASTER_REF
info "Deleting private data from master_work..."
pause
git filter-branch -f --prune-empty --index-filter 'git rm --cached --ignore-unmatch private/ -r' ${LATEST_MASTER_REF}..HEAD

# (re)create public_master_work from public_master
recreate_and_checkout "public_master_work" "public_master"

# update public_master_work from master
info "Cherry-picking from master_work into public_master_work..."
pause
git cherry-pick --keep-redundant-commits --allow-empty --strategy=recursive -X ours ${LATEST_MASTER_REF}..master_work

info "Clearing any empty commit in master_work..."
pause
git filter-branch -f --prune-empty ${LATEST_PUBLIC_MASTER_REF}..HEAD

# merge public_master_work into public_master (ff-only for safety)
info "update public_master"
pause
git checkout "public_master"
git merge --ff-only "public_master_work"

info "create refs"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/master" "master"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/public_master" "public_master"

# log created references
git for-each-ref --count=2 --sort=-refname "${REF_TREE_ROOT}"

info "done"
