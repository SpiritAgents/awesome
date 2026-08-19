#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/registry-common.sh"

# jq program: validates registry/catalog.json and every detail.json against the
# registry entries. Expects --slurpfile catalog / entries / details (each file
# holds one JSON value, read via [0]). Emits one error per line; empty output
# means everything is in sync.
read -r -d '' VALIDATE_REGISTRY_CONTENT_JQ <<'JQ' || true
$catalog[0] as $c |
$entries[0] as $es |
$details[0] as $ds |
($c.items // []) as $items |
[
  (if $c.schemaVersion != 1 then "registry/catalog.json has an unsupported schemaVersion." else empty end),
  (if ($c | has("items") | not) then "registry/catalog.json is missing the items array." else empty end),
  (if ($items | length) != ($es | length) then "registry/catalog.json item count (\($items | length)) does not match registry/extensions item count (\($es | length))." else empty end),
  ($items[] | (["extensionId", "packageName", "status", "featured", "defaultVersion", "defaultChannel", "defaultReviewStatus", "detailPath", "displayName", "description", "supportedHosts", "requestedCapabilities"] - keys)[] | "registry/catalog.json is missing required key '\(.)' on one or more items."),
  ($items | map(.extensionId) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "Duplicate extensionId '\(.)' found in registry/catalog.json."),
  ($es[] | . as $e |
    ($items | map(select(.extensionId == $e.extensionId))) as $m |
    (if ($m | length) == 0 then
      "registry/catalog.json is missing extensionId '\($e.extensionId)'."
    elif ($m | length) != 1 then
      "registry/catalog.json contains multiple items for extensionId '\($e.extensionId)'."
    else
      ($m[0]) as $ci |
      ($ds | map(select(.extensionId == $e.extensionId))) as $dm |
      (
        (["packageName", "status", "featured", "defaultVersion", "defaultReviewStatus"][] | . as $f | select($ci[$f] != $e[$f]) | "registry/catalog.json is out of sync for extensionId '\($e.extensionId)' field '\($f)'."),
        (([$e.versions[] | select(.version == $e.defaultVersion)][0].channel) as $ch |
          if $ci.defaultChannel != $ch then "registry/catalog.json is out of sync for extensionId '\($e.extensionId)' field 'defaultChannel'." else empty end),
        (if $ci.detailPath != "extensions/\($e.extensionId)/detail.json" then "registry/catalog.json has an unexpected detailPath for extensionId '\($e.extensionId)'." else empty end),
        (if ($dm | length) == 0 then
          "Missing detail artifact for extensionId '\($e.extensionId)'."
        else
          ($dm[0]) as $d |
          ($d.versions // []) as $dversions |
          (
            ((["schemaVersion", "extensionId", "packageName", "status", "featured", "defaultVersion", "defaultReviewStatus", "readmePath", "versions"] - ($d | keys))[] | "registry/extensions/\($e.extensionId)/detail.json is missing required key '\(.)'."),
            (["extensionId", "packageName", "status", "featured", "defaultVersion", "defaultReviewStatus"][] | . as $f | select($d[$f] != $e[$f]) | "registry/extensions/\($e.extensionId)/detail.json is out of sync for field '\($f)'."),
            (if $d.readmePath != "extensions/\($e.extensionId)/README.md" then "registry/extensions/\($e.extensionId)/detail.json has an unexpected readmePath." else empty end),
            (if ($dversions | length) != ($e.versions | length) then "registry/extensions/\($e.extensionId)/detail.json version count is out of sync." else empty end),
            ($dversions | map(select(.version == $e.defaultVersion))) as $ddvm |
            (if ($ddvm | length) == 0 then
              "registry/extensions/\($e.extensionId)/detail.json is missing defaultVersion '\($e.defaultVersion)'."
            else
              ($ddvm[0]) as $ddv |
              (
                (["displayName", "description", "supportedHosts", "requestedCapabilities"][] | . as $f |
                  if ($ddv | has($f) | not) then "registry/extensions/\($e.extensionId)/detail.json default version is missing '\($f)'."
                  elif $ci[$f] != $ddv[$f] then "registry/catalog.json is out of sync with detail artifact for extensionId '\($e.extensionId)' field '\($f)'."
                  else empty end),
                (["author", "homepageUrl", "repositoryUrl", "iconUrl"][] | . as $f |
                  if (($ci | has($f)) != ($ddv | has($f))) then "registry/catalog.json optional field '\($f)' is out of sync with detail artifact for extensionId '\($e.extensionId)'."
                  elif (($ci | has($f)) and ($ci[$f] != $ddv[$f])) then "registry/catalog.json optional field '\($f)' is out of sync with detail artifact for extensionId '\($e.extensionId)'."
                  else empty end),
                (if (($ci | has("keywords")) != ($ddv | has("keywords"))) then "registry/catalog.json keywords are out of sync with detail artifact for extensionId '\($e.extensionId)'."
                 elif (($ci | has("keywords")) and ($ci.keywords != $ddv.keywords)) then "registry/catalog.json keywords are out of sync with detail artifact for extensionId '\($e.extensionId)'."
                 else empty end),
                ($e.versions[] | . as $ev |
                  ($dversions | map(select(.version == $ev.version))) as $dv |
                  (if ($dv | length) != 1 then
                    "registry/extensions/\($e.extensionId)/detail.json has an invalid number of entries for version '\($ev.version)'."
                  else
                    ($dv[0]) as $dvv |
                    (
                      ((["version", "channel", "reviewStatus", "displayName", "description", "supportedHosts", "requestedCapabilities"] - ($dvv | keys))[] | "registry/extensions/\($e.extensionId)/detail.json is missing required version key '\(.)' for version '\($ev.version)'."),
                      (["version", "channel", "reviewStatus"][] | . as $f | select($dvv[$f] != $ev[$f]) | "registry/extensions/\($e.extensionId)/detail.json is out of sync for version '\($ev.version)' field '\($f)'."),
                      (if (($ev.changelog != null) != ($dvv.changelog != null)) then "registry/extensions/\($e.extensionId)/detail.json changelog presence is out of sync for version '\($ev.version)'."
                       elif ($ev.changelog != null) then
                         (["summary", "body"][] | . as $f | select($dvv.changelog[$f] != $ev.changelog[$f]) | "registry/extensions/\($e.extensionId)/detail.json changelog field '\($f)' is out of sync for version '\($ev.version)'.")
                       else empty end)
                    )
                  end))
              )
            end)
          )
        end)
      )
    end))
] | .[]
JQ

root=$(registry_root)
extensions_root="$root/registry/extensions"
catalog_path="$root/registry/catalog.json"

# Registries with many extensions exceed the per-argument size limit on Linux
# (128 KiB MAX_ARG_STRLEN), so pass the aggregated JSON via temp files instead
# of --argjson.
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/registry-validate.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

entries_file="$tmp_dir/entries.json"
load_registry_entries "$root" > "$entries_file"
entry_count=$(jq 'length' "$entries_file")

if [ ! -f "$catalog_path" ]; then
  echo 'registry/catalog.json is missing. Run ./scripts/build-catalog.sh to regenerate it.' >&2
  exit 1
fi

detail_count=$(find "$extensions_root" -type f -name detail.json | wc -l | tr -d ' ')
if [ "$detail_count" -ne "$entry_count" ]; then
  echo "registry/extensions/**/detail.json file count ($detail_count) does not match registry entry count ($entry_count)." >&2
  exit 1
fi

while IFS= read -r id; do
  if [ ! -f "$extensions_root/$id/README.md" ]; then
    echo "registry/extensions/$id/README.md is missing." >&2
    exit 1
  fi
  if [ ! -f "$extensions_root/$id/detail.json" ]; then
    echo "Missing detail artifact for extensionId '$id'." >&2
    exit 1
  fi
done < <(jq -r '.[].extensionId' "$entries_file")

details_file="$tmp_dir/details.json"
while IFS= read -r id; do
  cat "$extensions_root/$id/detail.json"
  echo
done < <(jq -r '.[].extensionId' "$entries_file") | jq -s -c '.' > "$details_file"

if ! errors=$(jq -n -r \
  --slurpfile catalog "$catalog_path" \
  --slurpfile entries "$entries_file" \
  --slurpfile details "$details_file" \
  "$VALIDATE_REGISTRY_CONTENT_JQ"); then
  echo "Failed to parse $catalog_path or a detail artifact; see the jq error above for the file." >&2
  exit 1
fi

if [ -n "$errors" ]; then
  printf '%s\n' "$errors" >&2
  exit 1
fi
