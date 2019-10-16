#!/bin/bash

##############################################################################################
##
## This script is intended to be run on a clone of repository SonarSource/sonar-enterprise 
## or slang-enterprise (later referenced as "the private repository").
##
## This script:
##   1- creates branch "public_[branch_name]" in the private repository and push it
##   2- creates public branch "[branch_name]" in the public repository and push it if it
##      doesn't exist yet
##   3- creates the initial synchronization references for branch "[branch_name]" in the private
##      repository and push them. Script sync_public_branch.sh relies on them to work
##
## This script will detect and fail:
##   1- if synchronization references are already present
##   2- if HEAD of public branch "[branch_name]" is not the synchronized commit
##
## parameters: 
##   PUBLIC_REMOTE: slang or sq
##   PUBLIC_REMOTE_URL: git@github.com:SonarSource/slang.git or git@github.com:SonarSource/sonarqube.git
##   BRANCH: master, branch-7.9, ...
##   BRANCH_REFERENCE: sha1 of the commit in branch "[branch_name]" in private repository to
##                     synchonize (can be different from the current head)
##   PUBLIC_BRANCH_HEAD: sha1 of the head commit of branch "[branch_name]" in public repository
##
##############################################################################################

set -euo pipefail

script_dir=$(dirname "${BASH_SOURCE[0]}")

source "${script_dir}/log_utils.sh"
source "${script_dir}/git_utils.sh"

create_and_push_ref() {
  local ref_name="${1}"
  local ref="${2}"
  local remote="${3}"

  git update-ref "${ref_name}" "${ref}"
  git push "${remote}" "${ref_name}"
}

PRIVATE_REMOTE="origin"
PUBLIC_REMOTE="${1}"
PUBLIC_REMOTE_URL="${2}"
BRANCH="${3}"
PUBLIC_BRANCH="public_${BRANCH}"
BRANCH_REFERENCE="${4}"
PUBLIC_BRANCH_HEAD="${5}"
REF_TREE_ROOT="refs/public_sync"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# just to predictively know on which branch we current are
git checkout master

info "Fetching branches and refs from remote ${PRIVATE_REMOTE}..."
git fetch --no-tags
git fetch --no-tags "${PRIVATE_REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"


info "Fetching branches from remote ${PUBLIC_REMOTE}..."
create_or_check_remote "${PUBLIC_REMOTE}" "${PUBLIC_REMOTE_URL}" || fatal "Remote ${PUBLIC_REMOTE} exists but does not have the expected URL"
git fetch --no-tags "${PUBLIC_REMOTE}"

# fail if private branch ${BRANCH} does not exist
branch_exists "${PRIVATE_REMOTE}/${BRANCH}" || fatal "Branch ${BRANCH} does not exist in private repository"

# fail if synchronzization is already initialized (even only partially)
private_references="$(git for-each-ref --count=1 "${REF_TREE_ROOT}/*/${BRANCH}")"
public_references="$(git for-each-ref --count=1 "${REF_TREE_ROOT}/*/${PUBLIC_BRANCH}")"
if [ "${private_references}" ] || [ "${public_references}" ]; then
  error "References already initialized for branch ${BRANCH} and/or branch ${PUBLIC_BRANCH}. See values below:"
  echo "${private_references}"
  echo "${public_references}"
  exit 1
fi

info "Initializing synchronization of branches ${PRIVATE_REMOTE}/${BRANCH} with ${PUBLIC_REMOTE}/${BRANCH} (${PUBLIC_REMOTE}=${PUBLIC_REMOTE_URL})..."
info "    Synchronized commit of private branch ${BRANCH} will be ${BRANCH_REFERENCE} \"$(commit "${BRANCH_REFERENCE}")\""
info "    Head of public branch ${BRANCH} and private branch ${PUBLIC_BRANCH} will be ${PUBLIC_BRANCH_HEAD} \"$(commit "${PUBLIC_BRANCH_HEAD}")\""
info ""
info "*******************************************************"
info "**** Caution: remote repositories will be modified ****"
info "*******************************************************"
info "Press enter to proceed, CTRL+C to quit"
read

# create/recreate ${BRANCH} and ${PUBLIC_BRANCH} locally
recreate_and_checkout "${BRANCH}" "${BRANCH_REFERENCE}"
recreate_and_checkout "${PUBLIC_BRANCH}" "${PUBLIC_BRANCH_HEAD}"

# if ${BRANCH} already exist in public repository, ensure its HEAD is ${PUBLIC_BRANCH_HEAD}"
if branch_exists "${PUBLIC_REMOTE}/${BRANCH}" && ! same_refs "${PUBLIC_REMOTE}/${BRANCH}" "${PUBLIC_BRANCH}"; then
  fatal "Head of ${PUBLIC_REMOTE}/${PUBLIC_BRANCH} ($(commit "${PUBLIC_REMOTE}/${branch}")) is not the expected commit ($(commit "${PUBLIC_BRANCH_HEAD}"))"
fi

info "Pushing ${PUBLIC_BRANCH} to private repository..."
git push "${PRIVATE_REMOTE}" "${PUBLIC_BRANCH}:${PUBLIC_BRANCH}"
info "Pushing ${BRANCH} to public repository..."
git push "${PUBLIC_REMOTE}" "${PUBLIC_BRANCH}:${BRANCH}"
info "Creating synchronization refs for branch ${BRANCH}..."
create_and_push_ref "${REF_TREE_ROOT}/${TIMESTAMP}/${BRANCH}" "${BRANCH_REFERENCE}" "${PRIVATE_REMOTE}"
create_and_push_ref "${REF_TREE_ROOT}/${TIMESTAMP}/${PUBLIC_BRANCH}" "${PUBLIC_BRANCH_HEAD}" "${PRIVATE_REMOTE}" 

info "done"

