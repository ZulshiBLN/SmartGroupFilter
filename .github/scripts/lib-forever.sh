# Sourced by the upload scripts and their controls: which WoW Forever game
# version a release is filed under on CurseForge and Wago. Plain bash, no jq,
# so the controls run anywhere.

TOC=SmartGroupFilter/SmartGroupFilter.toc

fail() { echo "UPLOAD FAILED: $*" >&2; exit 1; }

# A missing field is empty, so the caller's check names it: under set -e and
# pipefail, grep finding nothing would end the script without a word.
toc_field() { # value of a "## Field:" line of the TOC
    grep -m1 -E "^## $1:" "$TOC" | sed -E "s/^## $1:[[:space:]]*//" | tr -d '\r[:space:]' || true
}

# 16001 -> 1.60.1: the packager's mapping from a TOC interface to a game
# version (release.sh at the pinned commit, around line 1355).
interface_to_version() {
    local i="$1"
    printf '%d.%d.%d' "$((10#${i:0:-4}))" "$((10#${i: -4:2}))" "$((10#${i: -2:2}))"
}

# Picks the version to file under from the versions a site lists (stdin, one
# per line). Michel's rule of 2026-10-18, as the packager does it: the exact
# version; else the highest listed below it; else the highest listed - both
# with a warning. Nothing listed: fail. Versions compare numerically
# (sort -V); a string comparison would put 1.100.0 below 1.60.1.
resolve_game_version() {
    local target="$1" listed lower="" v
    listed=$(grep -v '^[[:space:]]*$' | sort -uV || true)
    [ -n "$listed" ] || { echo "UPLOAD FAILED: the site lists no WoW Forever version" >&2; return 1; }
    if grep -qxF "$target" <<< "$listed"; then
        echo "$target"
        return 0
    fi
    while IFS= read -r v; do
        [ "$(printf '%s\n%s\n' "$v" "$target" | sort -V | head -1)" = "$v" ] && lower="$v"
    done <<< "$listed"
    v=${lower:-$(tail -1 <<< "$listed")}
    echo "WARNING: WoW Forever $target is not listed; filing under $v" >&2
    echo "$v"
}
