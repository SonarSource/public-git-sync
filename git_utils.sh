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

