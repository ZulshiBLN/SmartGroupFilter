#!/usr/bin/env bash
# Refuses an upload script that could print a token. GitHub masks a secret it
# knows as ***, but a token that leaks into a log is still a leak, and a masked
# one hides that it happened (core: Secrets).
#
# Usage: check-no-token-output.sh <script>...
set -uo pipefail

patterns=(
    'set[[:space:]]+-[a-z]*x'                            # shell trace prints every expanded line
    'set[[:space:]]+-o[[:space:]]+xtrace'
    'curl.*[[:space:]](-v|--verbose|--trace|--trace-ascii)([[:space:]]|$)' # curl prints its headers
    '(echo|printf|cat)[^#]*(CF|WAGO)_API_TOKEN'           # a token handed to output
    '(^|[[:space:];|&])(env|printenv|declare[[:space:]]+-p)([[:space:]]*$|[[:space:]]*[;|&])'
)

found=0
for file in "$@"; do
    for p in "${patterns[@]}"; do
        if grep -nE "$p" "$file" >&2; then
            echo "TOKEN CHECK FAILED: $file matches '$p'" >&2
            found=1
        fi
    done
done
[ "$found" = 0 ] || exit 1
echo "token check passed: $*"
