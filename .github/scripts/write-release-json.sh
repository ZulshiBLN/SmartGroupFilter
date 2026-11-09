#!/usr/bin/env bash
# Writes release.json for a packaged zip, in the BigWigs packager's own format
# (its upload_github function). The packager writes the file only while it
# publishes, and this one has to be checked before anything is published.
# WowUp reads it to offer the release to a WoW Forever client (flavor forever).
#
# Usage: write-release-json.sh <zip> <version> <output>
set -euo pipefail

zip="$1"
version="$2"
out="$3"
toc="SmartGroupFilter/SmartGroupFilter.toc"

field() { # value of a "## Field:" line of the TOC
    grep -m1 -E "^## $1:" "$toc" | sed -E "s/^## $1:[[:space:]]*//" | tr -d '\r'
}

title=$(field Title)            # the packager's name field comes from the TOC title
interface=$(field Interface | tr -d '[:space:]')

case "$interface" in
    16???) flavor="forever" ;;  # the packager's mapping for WoW Forever
    *) echo "interface '$interface' is not WoW Forever (16xxx)" >&2; exit 1 ;;
esac

jq -n --arg name "$title" --arg version "$version" --arg filename "$(basename "$zip")" \
      --arg flavor "$flavor" --argjson interface "$interface" \
    '{ releases: [ { name: $name, version: $version, filename: $filename, nolib: false,
                     metadata: [ { flavor: $flavor, interface: $interface } ] } ] }' > "$out"
echo "release.json: $(basename "$zip"), $version, flavor $flavor, interface $interface"
