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
## repository public repository.
##
## parameters: 
## PUBLIC_REMOTE: slang or sq
## PUBLIC_REMOTE_URL: git@github.com:SonarSource/slang.git or git@github.com:SonarSource/sonarqube.git
##
##############################################################################################

set -euo pipefail

script_dir=$(dirname "${BASH_SOURCE[0]}")

cherry_pick_failed=
cherry_pick_sh=cherry-pick.$$.sh

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

# Verify that two refs are "public-equivalent": only have differences in private/
validate_public_equivalent_refs() {
  if git diff --name-only "$1" "$2" | grep -q "^private/"; then
    error "Illegal state: '$1' and '$2' should only differ in private/"
    info "Investigate the output of: git diff --name-only $1 $2"
    exit 1
  fi
}

commit() {
  git log -n 1 --pretty="%h - %s (%an %cr)" "$1"
}

has_single_parent() {
  local parents=$(git show -s --pretty=%P "$1")
  [[ $parents != *\ * ]]
}

REF_TREE_ROOT="refs/public_sync"
PRIVATE_REMOTE="origin"
PUBLIC_REMOTE=$1
PUBLIC_REMOTE_URL=$2

info "Fetching branches and refs from remote ${PRIVATE_REMOTE}..."
git fetch --no-tags "${PRIVATE_REMOTE}"
git fetch --no-tags "${PRIVATE_REMOTE}" "+${REF_TREE_ROOT}/*:${REF_TREE_ROOT}/*"

info "Ensuring master is up to date..."
git checkout "master" && git pull "${PRIVATE_REMOTE}" "master"

if ! git remote | grep -qxF "${PUBLIC_REMOTE}"; then
  info "Creating remote ${PUBLIC_REMOTE}..."
  git remote add "${PUBLIC_REMOTE}" "${PUBLIC_REMOTE_URL}"
fi

info "Fetching branches from remote ${PUBLIC_REMOTE}..."
git fetch --no-tags "${PUBLIC_REMOTE}"

# ensure we have an up to date local branch public_master of ${PUBLIC_REMOTE}/master
recreate_and_checkout "public_master" "${PUBLIC_REMOTE}/master"

validate_public_equivalent_refs "public_master" "master"

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
info "Cherry-picking from master_work (${LATEST_MASTER_REF}) into public_master_work..."
pause
for sha1 in $(git rev-list --reverse ${LATEST_MASTER_REF}..master_work); do
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
  info "Finally, run finish_sync_public_master.sh to complete the recovery."
  exit 1
fi

if [ ! "$cherry_pick_failed" ]; then
  rm "$cherry_pick_sh"
fi

"$script_dir/finish_sync_public_master.sh"
