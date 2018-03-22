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
  read
}

refresh_branch() {
  local BRANCH="$1"
  local NEW_HEAD="$2"

  info "refresh ${BRANCH} to ${NEW_HEAD}"
  if [ "$(git branch --list "${BRANCH}")" ]; then
    git branch -D "${BRANCH}"
  fi
  git checkout -b "${BRANCH}" "${NEW_HEAD}"
}

REF_TREE_ROOT="refs/public_sync"
REMOTE="origin"
SQ_REMOTE="sq"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

info "Fetching master..."
git checkout "master" && git pull "${REMOTE}" "master"

info "Creating SQ remote..."
if ! $(git remote | grep -qxF "${SQ_REMOTE}"); then
  git remote add "${SQ_REMOTE}" "git@github.com:SonarSource/sonarqube.git"
fi

info "Fetching ${SQ_REMOTE}/master and refs from remote..."
git fetch --no-tags "${SQ_REMOTE}"
git fetch --no-tags "${REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

# ensure we have an up to date local branch of ${SQ_REMOTE}/master
refresh_branch "public_master" "${SQ_REMOTE}/master"

info "Reading references..."
LATEST_PUBLIC_MASTER_REF="$(git for-each-ref --count=1 --sort=-refname 'refs/public_sync/*/public_master')"
LATEST_MASTER_REF="$(git for-each-ref --count=1 --sort=-refname 'refs/public_sync/*/master')"
LATEST_PUBLIC_MASTER_SYNC_DATE=$(echo "${LATEST_PUBLIC_MASTER_REF}" | cut -f 2 | cut -d '/' -f 3)
LATEST_MASTER_SYNC_DATE=$(echo "${LATEST_MASTER_REF}" | cut -f 2 | cut -d '/' -f 3)

if [ "${LATEST_PUBLIC_MASTER_SYNC_DATE}" != "${LATEST_MASTER_SYNC_DATE}" ]; then
  error "Sync date of master (${LATEST_MASTER_SYNC_DATE}) and public_master (${LATEST_PUBLIC_MASTER_SYNC_DATE}) are not consistent. Cannot proceed."
  exit 1
fi

LATEST_PUBLIC_MASTER_SHA1="${LATEST_PUBLIC_MASTER_REF%% *}"
LATEST_MASTER_SHA1="${LATEST_MASTER_REF%% *}"

LATEST_MASTER_COMMIT="$(git log -1 --pretty="%h - %s (%an %cr)" ${LATEST_MASTER_SHA1})"
LATEST_PUBLIC_MASTER_COMMIT="$(git log -1 --pretty="%h - %s (%an %cr)" ${LATEST_PUBLIC_MASTER_SHA1})"
info "Latest sync merged \"${LATEST_MASTER_COMMIT}\" into branch public_master as \"${LATEST_PUBLIC_MASTER_COMMIT}\" with timestamp \"${LATEST_MASTER_SYNC_DATE}\""

PUBLIC_MASTER_HEAD_SHA1="$(git log -1 --pretty="%H" "public_master")"
if [ "${PUBLIC_MASTER_HEAD_SHA1}" != "${LATEST_PUBLIC_MASTER_SHA1}" ]; then
  error "Latest reference to public master (${LATEST_PUBLIC_MASTER_SHA1}) is not HEAD of branch public_master. Previous run of synchonization script left an inconsistent state"
  exit 1
fi

MASTER_HEAD_SHA1=$(git log -1 --pretty="%H" "master")
if [ "$LATEST_MASTER_SHA1" = "$MASTER_HEAD_SHA1" ]; then
  info "no new commit to merge"
  exit 0
fi

MASTER_HEAD_COMMIT="$(git log -1 --pretty="%h - %s (%an %cr)" "${MASTER_HEAD_SHA1}")"
info "Merging \"${MASTER_HEAD_COMMIT}\" into branch public_master..."

# (re)create master_work
refresh_branch "master_work" "master"

pause
# remove private repo data since LATEST_MASTER_SHA1
info "deleting private data from master_work"
git filter-branch -f --prune-empty --index-filter 'git rm --cached --ignore-unmatch private/ -r' ${LATEST_MASTER_SHA1}..HEAD

pause
# (re)create public_master_work from public_master
refresh_branch "public_master_work" "public_master"

pause
# update public_master_work from master
git checkout "public_master_work"
info "cherry-picking from master_work into public_master_work"
git cherry-pick --allow-empty --strategy=recursive -X ours ${LATEST_MASTER_SHA1}..master_work

pause
info "clear any empty commit"
git filter-branch -f --prune-empty ${LATEST_PUBLIC_MASTER_SHA1}..HEAD

pause
# merge public_master_work into public_master (ff-only for safety)
info "update public_master"
git checkout "public_master"
git merge --ff-only "public_master_work"

info "create refs"
PUBLIC_MASTER_HEAD_SHA1="$(git log -1 --pretty="%H" "public_master")"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/master" "${MASTER_HEAD_SHA1}"
git update-ref "${REF_TREE_ROOT}/${TIMESTAMP}/public_master" "${PUBLIC_MASTER_HEAD_SHA1}"

# log created references
git for-each-ref --count=2 --sort=-refname 'refs/public_sync'

info "done"
