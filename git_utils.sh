#!/bin/bash

set -euo pipefail

commit() {
  local reference="${1}"
  git log -n 1 --pretty="%h - %s (%an %cr)" "${reference}"
}

sha1() {
  git rev-parse "$1"
}

same_refs() {
  [ "$(sha1 "$1")" = "$(sha1 "$2")" ]
}

remote_name_exists() {
  local remote_name="${1}"

  git remote | grep -qxF "${remote_name}"
}

remote_exists() {
  local remote_name="${1}"
  local remote_url="${2}"

  # counting matching lines to ensure both push and fetch are bound to the expected URL
  [ "$(git remote -v | grep -F "${remote_name}" | grep -F "${remote_url}" | wc -l)" = "2" ]
}

create_or_check_remote() {
  local remote_name="${1}"
  local remote_url="${2}"

  if remote_name_exists "${remote_name}"; then
    remote_exists "${remote_name}" "${remote_url}"
  else
    info "Creating remote ${remote_name} (${remote_url})..."
    git remote add "${remote_name}" "${remote_url}"
  fi
}

local_branch_exists() {
  local branch_name="${1}"

  [ "$(git branch --list "${branch_name}")" ]
}

branch_exists() {
  local branch_name="${1}"

  [ "$(git branch --list --all "${branch_name}")" ]
}


recreate_and_checkout() {
  local branch="$1"
  local new_head="$2"

  info "refresh ${branch} to ${new_head}"
  if local_branch_exists "${branch}"; then
    git branch -D "${branch}"
  fi
  # "--no-track" to not set upstream to avoid any push to the wrong remote by forcing push command to specify remote
  git checkout --no-track -b "${branch}" "${new_head}"
}

latest_ref() {
  local pattern="$1"
  git for-each-ref --count=1 --sort=-refname "$pattern" --format='%(refname)'
}

has_single_parent() {
  local parents=$(git show -s --pretty=%P "$1")
  [[ $parents != *\ * ]]
}

