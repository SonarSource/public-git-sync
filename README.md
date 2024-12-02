# Public-Git-Sync

aka the "Private to public Git repository synchronization tool"

This Git repository contains the source of the Public-Git-Sync tool.

## About

The purpose of Public-Git-Sync is to replicate the history of a branch with a given name from a private repository into a branch with the
same name in a public repository.

Public-Git-Sync works one branch at a time.

Public-Git-Sync relies on the assumption that content of directory `private` in the root of the private repository must not be made public.
Public-Git-Sync strips any private content from commits, and removes any commit which contains only private content, before pushing them to
the public repository.

The tool is made of 4 bash scripts to be called, **in order**:

1. `initialize_branch_synchronization.sh` to be called only once per branch to initialize Public-Git-Sync for this branch (see below "
   initialization")
2. `sync_public_branch.sh` to be called each time to synchronize a branch (see below "synchronization")
3. `finish_sync_public_branch.sh` called automatically by `sync_public_branch.sh` unless a manual operation is needed to complete
   synchronization (see below "cherry-pick conflicts")
4. `commit_sync_public_branch.sh` to be called after `sync_public_branch.sh` to commit synchronization to private and public remote
   repositories

**All scripts must be run from the root directory of a clone of the private repository**

# Modifications

## sonar-enterprise

The `sonar-enterprise` repository uses a modified version of this script, which excludes the GitHub Action workflows folder (
`.github/workflows`).
It is available on the `sonar-enterprise` branch.

# How to use

## Prerequisites

1. a private repository (eg. sonarsource/sonar-enterprise)
2. a public repository (eg. sonarsource/sonarqube)
3. a branch to synchronize in the private repository (e.g. master, branch-7.9, ...)
4. `bash` and `git` (configured to access both repositories)

## Initialization

Public-Git-Sync must be initialized for each branch (later referred to as `[branch_name]`).

The `initialize_branch_synchronization.sh` script will create:

1. a branch `[branch_name]` to synchronize to in the public repository
2. a branch named `public_[branch_name]` in the private repository which is the public version of `[branch_name]` in the private repository
3. a pair of initial synchronization Git references (these references are used to track previous synchronization points)

These elements are mandatory for `sync_public_branch.sh` to run.

To do the initialization, you will need:

1. the name of the branch to synchronize
2. a pair of commits (one private, one public) which you know are synchronized with each other (aka. a pair of "synchronized commits")

* when synchronizing master, it will likely be the first commit ever in master (assuming it has no content in `private` directory already)
* when synchronizing another branch than master, assuming master is synchronized, it will be the synchronized commits of the fork point of
  that branch with master

Here is an example of initialization with branch `branch-7.9` of the `sonar-enterprise` repository:

```bash
git clone --branch=sonar-enterprise git@github.com:sonarsource/public-git-sync.git synchronization
git clone git@github.com:sonarsource/sonar-enterprise.git
cd sonar-enterprise
# Usage:
#   initialize_branch_synchronization.sh PUBLIC_REMOTE_NAME PUBLIC_REMOTE_GIT_URL BRANCH_NAME PRIVATE_COMMIT_HASH PUBLIC_COMMIT_HASH
../synchronization/initialize_branch_synchronization.sh sq git@github.com:sonarsource/sonarqube.git branch-7.9 9d45cf3bd58bafc6acbfac447fc70a1b5fe2f050 0dc7f1ec3d08fd5cd39e23b35b236bbfa7ec8ae6
```

### Note on the synchronized commits

The synchronized commit of the private branch must (obviously) exist in the private repository. It has to belong to the synchronized branch
in the private repository (this is not currently enforced) but it doesn't have to be the HEAD of it.

The synchronized commit of the public branch can, but doesn't have to, exist in the private repository.

If it exists in the private repository, `initialize_branch_synchronization.sh` will be able to create the synchronized branch in the public
repository for you. If it doesn't, then synchronized branch in the public repository must exist and this commit must be the HEAD of it.

### Note on branches

Current implementation of `initialize_branch_synchronization.sh` will fail if `[branch_name]` or `public_[branch_name]` exist and can't be
updated to the specified commits (i.e. it performs a default `git push`).

## Synchronization

`sync_public_branch.sh` is the bash script you want to call on a regular basis, most likely through an automated task.

To run this script, you will need:

1. the name of the branch to synchronize
2. to have initialized Public-Git-Sync on this branch (see above "Initialization")

`sync_public_branch.sh` does not make any change to the remote public and private repositories. All changes are local to the current clone
of the private repository.

To "commit" these changes to the remote public and private repositories, you must call `commit_sync_public_branch.sh` (or do it manually,
not advised).

Here is an example of synchronization of branch `branch-7.9` of the `sonar-enterprise` repository:

```bash
git clone --branch=sonar-enterprise git@github.com:sonarsource/public-git-sync.git synchronization
git clone git@github.com:sonarsource/sonar-enterprise.git
cd sonar-enterprise
../synchronization/sync_public_branch.sh sq git@github.com:sonarsource/sonarqube.git branch-7.9
../synchronization/commit_sync_public_branch.sh sq branch-7.9
```

### cherry-pick conflicts

It may happen that `sync_public_branch.sh` fails to perform automatically all operations to create the public version of `[branch_name]`.
Most specifically, these would be `cherry-pick` commands which can't be made automatically by Git.

In such case, `sync_public_branch.sh` will stop prematurely with a message such as the following:

```
Resolve the current cherry-pick, and then run bash cherry-pick.branch-7.9.8325.sh to continue.
Finally, run 'finish_sync_public_branch.sh branch-7.9' to complete the recovery.
```

To investigate and resolve the conflict:

* use `git status`, `git diff`, edit files as necessary and then use `git cherry-pick --continue`
* execute the indicated script: `./cherry-pick.branch-7.9.8325.sh` which will apply the following cherry-pick commands
* execute `finish_sync_public_branch.sh branch-7.9` as indicated to finalize the sync
* finally, as when `sync_public_branch.sh` succeeds, you will have to call `commit_sync_public_branch.sh` to push synchronization results to
  public and private remote repositories

### Note about `finish_sync_public_branch.sh`

Under regular operation of Public-Git-Sync, you won't have to call the `finish_sync_public_branch.sh` script.

This script only exists apart from `sync_public_branch.sh` to provide an easy procedure to recover a cherry-pick conflicts (see above).

# How it works

## Replicating a tree of commits

What Public-Git-Sync basically does is to replicate a tree of commits into another tree of commits (so, keeping the order) excluding all
changes which apply to the `private` directory.

To illustrate, take the following trees of two synchronized private and public branches:

> `A`, `B`, `C`, ... are the sha1 of the commits and `change A`, `change B`, `change C`, ... are the title of the commits

```
  public branch               private branch
       A change A                  A' change A
       |                           |
       B change B                  B' change B
       |                           |
       C change C                  |
       |                           |
       D change D                  D' change D
       |                           |
       E change E                  E' change E
       |                           |
       F change F                  F' change F
```

Several observations:

1. the title and the order of the commits are preserved (so are the authors, emails, etc.)
2. there is no commit `C'` because this commit contained only private content
3. any of the commits `B'` to `F'` could have the same content as respectively, `B` to `F`, they will still have a different sha1 because
   their parent is not the same as in the public branch

### Notes on merge commits

In the example above, each commit has a single parent. This is not the case for merge commits.

Public-Git-Sync handles merge commits by taking only one parent into account. This implies that merge commit will be there, unless it's
empty/has only private content, and will lose the information of the other parent.

### Technical details

Public-Git-Sync relies on Git commands `filter-branch` and `cherry-pick` and a pair of work branches (called `[branch_name]_work` and
`public_[branch_name]_work`).

The `sync_public_branch.sh` script does the following (on top of some sanity checks):

1. (re)create branch `[branch_name]_work` as a copy of `[branch_name]`
2. use `git filter-branch` to remove any private content from the last synchronized commit to the HEAD of `[branch_name]_work`
    * this creates commits without private content
    * and also some empty commits which had only private content
3. (re)create branch `public_[branch_name]_work` from `public_[branch_name]`
4. apply in order, with `git cherry-pick`, the filtered commits from `[branch_name]_work` into `public_[branch_name]`
    * these are the operations which may require manual fix by user to complete
    * this branch can contain empty commits at this stage

The `finish_sync_public_branch.sh` is then called and does the following:

1. remove empty commits from `public_[branch_name]_work` using `git filter-branch`
    * in the example above, `C'` did exist for a while but is deleted at this stage
2. update local branch `public_[branch_name]` to now be the same as `public_[branch_name]_work`
3. perform a sanity check to ensure **no private content are present in `public_[branch_name]`**
4. create synchronization refs to the HEADs of `[branch_name]` and `public_[branch_name]`

So far, all changes made are local to the current clone of the private repository.

They can be reviewed or discarded by simply deleting the clone.

To push the changes to the remote public and private repositories, use `commit_sync_public_branch.sh` which does the following:

1. push branch `public_[branch_name]` to private repository
2. push branch `[branch_name]` to public repository with content of `public_[branch_name]`
3. push the synchronization refs

### Note on `commit_sync_public_branch.sh`

`commit_sync_public_branch.sh` will have no effect if there is nothing to push. It can be safely called after a call of
`sync_public_branch.sh` which found nothing to synchronize.

`commit_sync_public_branch.sh` will push all synchronization refs not yet present in remote private repository, not only those created by
the previous synchronization (i.e. it's stateless). This implies it can be used to push at once multiple synchronizations (this is not
advised, though).

## Keeping track of synchronized commits

The second important feature of Public-Git-Sync is to keep track of synchronized commits.

This way, `sync_public_branch.sh` can:

1. synchronize only the new commits from the private branch
2. detect there is nothing new to synchronize
3. prevent synchronisation time to increase (linearly or worse) with the number of commits in `[branch_name]`
4. prevent possible rewriting (new sha1) of already synchronized commits and a lot of messy consequences that would have
5. rely on safe and simple `git push --forward-only` to publish to the public repository

Public-Git-Sync achieves this by storing Git references (later referenced to as "synchronization refs") in the private repository. These
references are stored in `refs/public_sync`.

Synchronization refs always go by two: one pointing to a commit in the private branch, one pointing to a commit in the public branch.

These two commits are referred to as "synchronized commits". You can consider synchronized commits as one commit being the public version of
the other.

Let's have a look at a sequence of synchronization calls over time for the example above.

Initialization

```
  public branch               private branch                synchronized commits
       A change A                  A' change A                   A -> A'
```

Synchronizing `B`

```
  public branch               private branch                synchronized commits
       A change A                  A' change A                   A -> A'
       |                           |
       B change B                  B' change B                   B -> B'
```

Synchronizing `C`

> since `C` has no public content, no new commit will be pushed to the public branch. The synchronized commit for `C` is therefor the
> current HEAD of the public branch: `B'`

```
  public branch               private branch                synchronized commits
       A change A                  A' change A                   A -> A'
       |                           |
       B change B                  B' change B                   B -> B'
       |                           |
       C change C                  |                             C -> B'
```

Synchronizing `F`

> since the last synchronized commit is `C`, all commits since `C` will be synchronized: `D`, `E` and `F`. Public-Git-Sync will create
> synchronization refs only for the HEADs: `F` and `F'`.

```
  public branch               private branch                synchronized commits
       A change A                  A' change A                   A -> A'
       |                           |
       B change B                  B' change B                   B -> B'
       |                           |
       C change C                  |                             C -> B'
       |                           |
       D change D                  D' change D
       |                           |
       E change E                  E' change E
       |                           |
       F change F                  F' change F                   F -> F'
```

### Technical details

Synchronization refs are stored in the ref directory `refs/public_sync`.

Refs to synchronized commits are stored in a subdirectory which name is a timestamp, e.g.: `2019-10-16_13-41-03`. Timestamp allows to sort
references and identify the most recent ones. The timestamp is basically the time when `sync_public_branch.sh` is called.

In this directory, each synchronized commit has its reference named after the branch it belongs to.

Currently, synchronization refs are stored forever. An improvement issue ([#6](https://github.com/sonarsource/public-git-sync/issues/6)) has
been filled.

### Note on clone and fork

Git clone does not pull synchronization refs by default. They have to be pulled explicitly.

Example:

```
git fetch --no-tags origin "+refs/public_sync/*:refs/public_sync/*"
```

GitHub does not copy synchronization refs when forking a repository. They will have to be copied manually.

## License

Copyright 2018-2020.

Licensed under the [GNU Lesser General Public License, Version 3.0](http://www.gnu.org/licenses/lgpl.txt)

## Authors

Sébastien Lesaint and Janos Gyerik
