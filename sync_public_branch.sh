#!/bin/bash


##############################################################################################
##
## This script is intended to be run on a clone of a private repository such as
## SonarSource/sonar-enterprise.
## This script requires that script init_branches.sh has been run prior to being called.
##
## This script updates branch "public_[branch_name]" in the private repository with latest
## changes from "[branch_name]" which apply only to public content.
##
## Branch "public_[branch_name]" can then be merged fast-forward only into branch
## "[branch_name]" of the public repository.
##
## parameters: 
## PUBLIC_REMOTE: slang or sq
## PUBLIC_REMOTE_URL: git@github.com:SonarSource/slang.git or git@github.com:SonarSource/sonarqube.git
## BRANCH: master, branch-7.9, ...
##
##############################################################################################

set -euo pipefail

script_dir=$(dirname "${BASH_SOURCE[0]}")

source "${script_dir}/log_utils.sh"
source "${script_dir}/git_utils.sh"

REF_TREE_ROOT="refs/public_sync"
PRIVATE_REMOTE="origin"
PUBLIC_REMOTE="${1}"
PUBLIC_REMOTE_URL="${2}"
BRANCH="${3}"
WORK_BRANCH="${BRANCH}_work"
PUBLIC_BRANCH="public_${BRANCH}"
PUBLIC_WORK_BRANCH="public_${BRANCH}_work"

cherry_pick_failed=
cherry_pick_sh=cherry-pick.${BRANCH}.$$.sh

# create script header where cherry-pick commands will be appended
# to help recovery in case of a failure in the cherry-picking step
cat << "EOF" > "$cherry_pick_sh"
#!/bin/bash

set -xeuo pipefail

EOF

cherry_pick() {
  if [ ! "$cherry_pick_failed" ]; then
    if ! git cherry-pick "$@"; then
      cherry_pick_failed=yes
    fi
  else
    echo "git cherry-pick $@" >> "$cherry_pick_sh"
  fi
}

pause() {
  echo "pause..."
#  read
}

sync_date() {
  local ref="$1"
  cut -d/ -f3 <<< "$ref"
}

info "Fetching branches and refs from remote ${PRIVATE_REMOTE}..."
git fetch --no-tags "${PRIVATE_REMOTE}"
git fetch --no-tags "${PRIVATE_REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

info "Ensuring ${BRANCH} is up to date..."
git checkout "${BRANCH}" && git pull "${PRIVATE_REMOTE}" "${BRANCH}"

if ! git remote | grep -qxF "${PUBLIC_REMOTE}"; then
  info "Creating remote ${PUBLIC_REMOTE}..."
  git remote add "${PUBLIC_REMOTE}" "${PUBLIC_REMOTE_URL}"
fi

info "Fetching branches from remote ${PUBLIC_REMOTE}..."
git fetch --no-tags "${PUBLIC_REMOTE}"

# ensure we have an up to date local branch ${PUBLIC_BRANCH} of ${PUBLIC_REMOTE}/${BRANCH}
recreate_and_checkout "${PUBLIC_BRANCH}" "${PUBLIC_REMOTE}/${BRANCH}"

info "Reading references..."
LATEST_PUBLIC_BRANCH_REF="$(latest_ref "${REF_TREE_ROOT}/*/${PUBLIC_BRANCH}")"
LATEST_BRANCH_REF="$(latest_ref "${REF_TREE_ROOT}/*/${BRANCH}")"
LATEST_PUBLIC_BRANCH_SYNC_DATE=$(sync_date "${LATEST_PUBLIC_BRANCH_REF}")
LATEST_BRANCH_SYNC_DATE=$(sync_date "${LATEST_BRANCH_REF}")

if [ "${LATEST_PUBLIC_BRANCH_SYNC_DATE}" != "${LATEST_BRANCH_SYNC_DATE}" ]; then
  error "Sync date of ${BRANCH} (${LATEST_BRANCH_SYNC_DATE}) and ${PUBLIC_BRANCH} (${LATEST_PUBLIC_BRANCH_SYNC_DATE}) are not consistent. Cannot proceed."
  exit 1
fi

info "Latest sync merged \"$(commit "${LATEST_BRANCH_REF}")\" into branch ${PUBLIC_BRANCH} as \"$(commit "${LATEST_PUBLIC_BRANCH_REF}")\" with timestamp \"${LATEST_BRANCH_SYNC_DATE}\""

if ! same_refs "${PUBLIC_BRANCH}" "${LATEST_PUBLIC_BRANCH_REF}"; then
  error "Latest reference to public ${BRANCH} ($(sha1 "${LATEST_PUBLIC_BRANCH_REF}")) is not HEAD of branch ${PUBLIC_BRANCH}. Previous run of synchonization script left an inconsistent state"
  exit 1
fi

if same_refs "${BRANCH}" "${LATEST_BRANCH_REF}"; then
  info "no new commit to merge"
  rm "$cherry_pick_sh"
  exit 0
fi

info "Synchronizing \"$(commit "${BRANCH}")\" into branch ${PUBLIC_BRANCH}..."

# (re)create ${WORK_BRANCH}
recreate_and_checkout "${WORK_BRANCH}" "${BRANCH}"

# remove private repo data since LATEST_BRANCH_REF
info "Deleting private data from ${WORK_BRANCH}..."
pause
git filter-branch -f --prune-empty --index-filter 'git rm --cached --ignore-unmatch private/ -r' ${LATEST_BRANCH_REF}..HEAD

# (re)create ${PUBLIC_WORK_BRANCH} from ${PUBLIC_BRANCH}
recreate_and_checkout "${PUBLIC_WORK_BRANCH}" "${PUBLIC_BRANCH}"

# update ${PUBLIC_WORK_BRANCH} from ${BRANCH}
info "Cherry-picking from ${WORK_BRANCH} (${LATEST_BRANCH_REF}) into ${PUBLIC_WORK_BRANCH}..."
pause
for sha1 in $(git rev-list --reverse ${LATEST_BRANCH_REF}..${WORK_BRANCH}); do
  if has_single_parent "$sha1"; then
    mainline_args=
  else
    mainline_args='-m 2'
  fi
  cherry_pick --keep-redundant-commits --allow-empty --strategy=recursive -X ours $mainline_args "$sha1"
done

if [ "$cherry_pick_failed" ]; then
  error "Failure was detected during cherry-pick, aborting."
  info "Resolve the current cherry-pick, and then run bash $cherry_pick_sh to continue."
  info "Finally, run 'finish_sync_public_branch.sh ${BRANCH}' to complete the recovery."
  exit 1
else
  rm "$cherry_pick_sh"
fi


"$script_dir/finish_sync_public_branch.sh" "${BRANCH}"
