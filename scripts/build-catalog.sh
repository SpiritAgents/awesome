#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/registry-common.sh"

# jq program: builds the detail versions array for one entry. Input is the
# entry object; expects --argjson doc (npm registry document) and
# --arg pkg (package name). Aborts with error(...) on missing metadata.
read -r -d '' BUILD_DETAIL_VERSIONS_JQ <<'JQ' || true
def repo_url($r):
  if $r == null then null
  else
    (if ($r | type) == "string" then $r
     elif (($r | type) == "object") and (($r.url // null) != null) then ($r.url | tostring)
     else null end) as $u |
    if ($u == null) or ($u | test("^\\s*$")) then null
    else $u | sub("^git\\+"; "") | sub("^git://github\\.com/"; "https://github.com/") | sub("\\.git$"; "")
    end
  end;

def icon_url($pkg; $version; $icon):
  if ($icon == null) or (($icon | tostring | test("^\\s*$"))) then null
  else "https://cdn.jsdelivr.net/npm/\($pkg)@\($version)/\($icon | tostring | sub("^[./]+"; "") | gsub("\\\\"; "/"))"
  end;

. as $e |
($doc.versions // {}) as $vs |
($doc.time // {}) as $time |
[
  $e.versions[] | . as $ev |
  ($ev.version | tostring) as $version |
  ($vs[$version]) as $manifest |
  if $manifest == null then error("Version '\($version)' was not found in npm metadata for \($pkg).")
  else
    ($manifest.spiritExtension) as $se |
    if $se == null then error("Package \($pkg)@\($version) is missing package.json spiritExtension metadata.")
    else
      (($se.displayName // "") | tostring) as $displayName |
      if ($displayName | test("^\\s*$")) then error("Package \($pkg)@\($version) is missing spiritExtension.displayName.")
      else
        ($manifest.dist // {}) as $dist |
        ({
          version: $version,
          channel: ($ev.channel | tostring),
          reviewStatus: ($ev.reviewStatus | tostring),
          displayName: $displayName,
          description: (if $manifest.description == null then "" else ($manifest.description | tostring) end),
          author: (if $manifest.author == null then null
                   elif ($manifest.author | type) == "string" then $manifest.author
                   elif (($manifest.author | type) == "object") and (($manifest.author.name // null) != null) then ($manifest.author.name | tostring)
                   else null end),
          homepageUrl: (if $manifest.homepage == null then null else ($manifest.homepage | tostring) end),
          repositoryUrl: repo_url($manifest.repository),
          keywords: (if $manifest.keywords == null then [] else [$manifest.keywords[] | tostring] end),
          supportedHosts: (if $se.supportedHosts == null then [] else [$se.supportedHosts[] | tostring] end),
          requestedCapabilities: (if $se.requestedCapabilities == null then [] else [$se.requestedCapabilities[] | tostring] end),
          iconUrl: icon_url($pkg; $version; $se.icon),
          publishedAt: (if $time[$version] == null then null else ($time[$version] | tostring) end),
          tarballUrl: (if $dist.tarball == null then null else ($dist.tarball | tostring) end),
          integrity: (if $dist.integrity == null then null else ($dist.integrity | tostring) end),
          shasum: (if $dist.shasum == null then null else ($dist.shasum | tostring) end)
        }
        | del((.author, .homepageUrl, .repositoryUrl, .iconUrl, .publishedAt, .tarballUrl, .integrity, .shasum) | select(. == null or (tostring | test("^\\s*$"))))
        | (if (.keywords | length) == 0 then del(.keywords) else . end)
        | (if $ev.changelog != null then . + {changelog: {summary: ($ev.changelog.summary | tostring), body: ($ev.changelog.body | tostring)}} else . end))
      end
    end
  end
]
JQ

# jq program: builds the detail.json document for one entry. Expects
# --argjson e (entry) and --argjson versions (detail versions array).
read -r -d '' BUILD_DETAIL_DOC_JQ <<'JQ' || true
{
  "$schema": "../../../schemas/marketplace-detail.schema.json",
  schemaVersion: 1,
  extensionId: $e.extensionId,
  packageName: $e.packageName,
  status: $e.status,
  featured: $e.featured,
  defaultVersion: ($e.defaultVersion | tostring),
  defaultReviewStatus: ($e.defaultReviewStatus | tostring),
  readmePath: "extensions/\($e.extensionId)/README.md",
  versions: $versions
}
JQ

# jq program: builds the catalog item for one entry. Expects --argjson e
# (entry) and --argjson versions (detail versions array).
read -r -d '' BUILD_CATALOG_ITEM_JQ <<'JQ' || true
([$e.versions[] | select(.version == $e.defaultVersion)][0]) as $dev |
([$versions[] | select(.version == $e.defaultVersion)][0]) as $ddv |
if $ddv == null then error("defaultVersion '\($e.defaultVersion)' was not found in generated detail versions for extensionId '\($e.extensionId)'.")
else
  ({
    extensionId: $e.extensionId,
    packageName: $e.packageName,
    status: $e.status,
    featured: $e.featured,
    defaultVersion: ($e.defaultVersion | tostring),
    defaultChannel: ($dev.channel | tostring),
    defaultReviewStatus: ($e.defaultReviewStatus | tostring),
    detailPath: "extensions/\($e.extensionId)/detail.json",
    displayName: ($ddv.displayName | tostring),
    description: ($ddv.description | tostring),
    author: ($ddv.author // null),
    homepageUrl: ($ddv.homepageUrl // null),
    repositoryUrl: ($ddv.repositoryUrl // null),
    keywords: ($ddv.keywords // null),
    supportedHosts: $ddv.supportedHosts,
    requestedCapabilities: $ddv.requestedCapabilities,
    iconUrl: ($ddv.iconUrl // null)
  }
  | del((.author, .homepageUrl, .repositoryUrl, .iconUrl) | select(. == null or (tostring | test("^\\s*$"))))
  | (if (.keywords == null) or ((.keywords | length) == 0) then del(.keywords) else . end))
end
JQ

root=$(registry_root)
extensions_root="$root/registry/extensions"
catalog_path="$root/registry/catalog.json"

entries=$(load_registry_entries "$root")

# Delete stale detail artifacts only after all entries validated, so a failed
# build never leaves the tree with missing details and a stale catalog.
find "$extensions_root" -type f -name detail.json -delete

catalog_items='[]'
while IFS= read -r entry; do
  id=$(jq -r '.extensionId' <<< "$entry")
  package_name=$(jq -r '.packageName' <<< "$entry")

  readme_path="$extensions_root/$id/README.md"
  if [ ! -f "$readme_path" ]; then
    echo "Missing README.md for extensionId '$id' at '$readme_path'." >&2
    exit 1
  fi

  if ! npm_doc=$(fetch_package_document "$package_name"); then
    echo "Failed to fetch npm metadata for $package_name." >&2
    exit 1
  fi

  detail_versions=$(jq -c --argjson doc "$npm_doc" --arg pkg "$package_name" "$BUILD_DETAIL_VERSIONS_JQ" <<< "$entry")

  detail_dir="$extensions_root/$id"
  mkdir -p "$detail_dir"
  # Generated artifacts end with a trailing blank line; keep that byte format stable.
  { jq -n --argjson e "$entry" --argjson versions "$detail_versions" "$BUILD_DETAIL_DOC_JQ"; echo; } > "$detail_dir/detail.json"

  catalog_item=$(jq -c -n --argjson e "$entry" --argjson versions "$detail_versions" "$BUILD_CATALOG_ITEM_JQ")
  catalog_items=$(jq -c --argjson item "$catalog_item" '. + [$item]' <<< "$catalog_items")
done < <(jq -c '.[]' <<< "$entries")

{ jq -n --argjson items "$catalog_items" '{
  "$schema": "../schemas/marketplace-catalog.schema.json",
  schemaVersion: 1,
  items: ($items | sort_by(.extensionId))
}'; echo; } > "$catalog_path"
