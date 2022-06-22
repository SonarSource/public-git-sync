#!/bin/bash


##############################################################################################
##
## This script is intended to be run on a clone of a private repository such as
## SonarSource/sonar-enterprise or slang-enterprise
##
## This script commits work of init_branches.sh and sync_public_branch.sh by pushing:
##  1- branch public_[branch_name] to private repository's public_[branch_name]
##  2- branch public_[branch_name] to public repository's [branch_name]
##  3- the references used by sync_public_branch.sh to the private repository
##
## parameters: 
## PUBLIC_REMOTE: slang or sq
## BRANCH: master, branch-7.9, ...
##
##############################################################################################

set -euo pipefail

script_dir=$(dirname "${BASH_SOURCE[0]}")

source "${script_dir}/log_utils.sh"
source "${script_dir}/git_utils.sh"

PUBLIC_REMOTE="${1}"
PRIVATE_REMOTE="origin"
REF_TREE_ROOT="refs/public_sync"
BRANCH="${2}"
PUBLIC_BRANCH="public_${BRANCH}"

# to know where we are
git checkout "${PUBLIC_BRANCH}"

info "Pushing ${PUBLIC_BRANCH} to private repository..."
git push "${PRIVATE_REMOTE}" "${PUBLIC_BRANCH}:${PUBLIC_BRANCH}"

info "Pushing refs to private repository..."
TMP_EXISTING_REFS_FILE=$(mktemp)
git ls-remote "${PRIVATE_REMOTE}" | cut -f 2 | grep "^${REF_TREE_ROOT}/" > ${TMP_EXISTING_REFS_FILE} || true
for ref in $(git for-each-ref "${REF_TREE_ROOT}" | cut -f 2 | grep -v --file="${TMP_EXISTING_REFS_FILE}"); do
  echo "committing ref $ref"
  git push "${PRIVATE_REMOTE}" "${ref}"
done

info "Pushing ${BRANCH} to public repository..."
git push "${PUBLIC_REMOTE}" "${PUBLIC_BRANCH}:${BRANCH}"

info "done"
