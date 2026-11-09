#!/usr/bin/env bash
# Refuses a commit that is not a release merge in main - the rule pre-push
# applies to v* tags, here for a tag that never met the hook, e.g. one created
# on GitHub. Needs the full history and origin/main (checkout fetch-depth 0).
#
# Usage: check-release-ref.sh <commit>
set -euo pipefail

commit=$(git rev-parse --verify --quiet "$1^{commit}") || { echo "REFUSED: '$1' is no commit" >&2; exit 1; }
parents=$(( $(git rev-list --parents -n 1 "$commit" | wc -w) - 1 ))

if [ "$parents" -lt 2 ]; then
    echo "REFUSED: $commit has $parents parent(s); a release is a merge of develop into main" >&2
    exit 1
fi
if ! git merge-base --is-ancestor "$commit" refs/remotes/origin/main; then
    echo "REFUSED: $commit is a merge, but not on main" >&2
    exit 1
fi
echo "release ref accepted: $commit is a merge on main"
