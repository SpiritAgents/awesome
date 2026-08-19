#!/usr/bin/env bash
# Shared helpers for the registry bash scripts. Source this file; do not execute it directly.

# Root of the repository, derived from this script's location.
registry_root() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  (cd "$script_dir/.." && pwd)
}

# Prints the registry/extensions/**/entry.json paths, sorted by full path.
list_entry_files() {
  local root=$1
  local files
  files=$(find "$root/registry/extensions" -type f -name entry.json | LC_ALL=C sort)
  if [ -z "$files" ]; then
    echo 'No registry entry files found under registry/extensions/**/entry.json.' >&2
    return 1
  fi
  printf '%s\n' "$files"
}

# Reads a newline-separated list of JSON file paths from stdin and writes their
# concatenated contents (one JSON text per line) to stdout for jq slurping.
concat_json_files() {
  local f
  while IFS= read -r f; do
    cat "$f"
    echo
  done
}

# Fetches the npm registry document for a package name.
fetch_package_document() {
  local package_name=$1
  local encoded_name
  encoded_name=$(jq -rn --arg p "$package_name" '$p | @uri')
  curl -fsSL "https://registry.npmjs.org/$encoded_name"
}

# jq program: validates one registry entry object. Emits one error per line;
# empty output means the entry is valid. Expects --arg f <file name>.
read -r -d '' REGISTRY_ENTRY_ASSERT_JQ <<'JQ' || true
. as $e |
[
  (if $e.schemaVersion != 1 then "Unsupported schemaVersion in \($f)." else empty end),
  ((["extensionId", "packageName", "status", "featured", "defaultVersion", "versions"] - ($e | keys))[] | "Missing required key '\(.)' in \($f)."),
  (if (($e.extensionId // "") | tostring | test("^\\s*$")) then "extensionId must be a non-empty string in \($f)." else empty end),
  (if (($e.packageName // "") | tostring | test("^\\s*$")) then "packageName must be a non-empty string in \($f)." else empty end),
  (if (($e.defaultVersion // "") | tostring | test("^\\s*$")) then "defaultVersion must be a non-empty string in \($f)." else empty end),
  (if (($e.defaultReviewStatus // "") | tostring | test("^\\s*$")) then "defaultReviewStatus must be a non-empty string in \($f)." else empty end),
  (if (($e | has("status")) and ((["listed", "hidden", "deprecated", "blocked"] | index($e.status)) == null)) then "Invalid status '\($e.status)' in \($f). Allowed values: listed, hidden, deprecated, blocked." else empty end),
  (if (($e | has("featured")) and (($e.featured | type) != "boolean")) then "featured must be a boolean in \($f)." else empty end),
  (if (($e | has("defaultReviewStatus")) and (((($e.defaultReviewStatus // "") | tostring | test("^\\s*$")) | not)) and ((["unverified", "verified", "revoked"] | index($e.defaultReviewStatus)) == null)) then "Invalid defaultReviewStatus '\($e.defaultReviewStatus)' in \($f). Allowed values: unverified, verified, revoked." else empty end),
  (if (($e | has("versions") | not) or (($e.versions | type) != "array") or (($e.versions | length) == 0)) then
    "versions must contain at least one item in \($f)."
  else
    (
      ($e.versions[] | . as $v |
        if (($v | type) != "object") then
          "Missing required version key 'version' in \($f)."
        else
          (
            ((["version", "channel", "reviewStatus"] - ($v | keys))[] | "Missing required version key '\(.)' in \($f)."),
            (if (($v.version // "") | tostring | test("^\\s*$")) then "version must be a non-empty string in \($f)." else empty end),
            (if (($v | has("channel")) and ((["stable", "preview", "experimental"] | index($v.channel)) == null)) then "Invalid channel '\($v.channel)' in \($f). Allowed values: stable, preview, experimental." else empty end),
            (if (($v | has("reviewStatus")) and ((["unverified", "verified", "revoked"] | index($v.reviewStatus)) == null)) then "Invalid reviewStatus '\($v.reviewStatus)' in \($f). Allowed values: unverified, verified, revoked." else empty end),
            (if ($v.changelog != null) then
              if (($v.changelog | type) != "object") then
                "changelog must be an object in \($f)."
              else
                (
                  ((["summary", "body"] - ($v.changelog | keys))[] | "Missing required changelog key '\(.)' in \($f)."),
                  (if (($v.changelog.summary // "") | tostring | test("^\\s*$")) then "changelog.summary must be a non-empty string in \($f)." else empty end),
                  (if (($v.changelog.body // "") | tostring | test("^\\s*$")) then "changelog.body must be a non-empty string in \($f)." else empty end)
                )
              end
            else empty end)
          )
        end),
      ($e.versions | map(if (type == "object") then .version else null end) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "Duplicate version '\(.)' found in \($f)."),
      (if (($e.versions | map(if (type == "object") then .version else null end) | index($e.defaultVersion)) == null) then "defaultVersion '\($e.defaultVersion)' was not found in the versions list for \($f)." else empty end)
    )
  end)
] | .[]
JQ

# jq program: checks a slurped array of entries for duplicate extensionId and
# packageName values. Emits one error per line; empty output means unique.
read -r -d '' REGISTRY_ENTRY_DUP_JQ <<'JQ' || true
(map(.extensionId) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "Duplicate extensionId '\(.)' found."),
(map(.packageName) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "Duplicate packageName '\(.)' found.")
JQ

# Validates a single entry file against REGISTRY_ENTRY_ASSERT_JQ.
assert_registry_entry() {
  local file=$1
  local errors
  if ! errors=$(jq -r --arg f "$file" "$REGISTRY_ENTRY_ASSERT_JQ" "$file"); then
    echo "Failed to parse $file." >&2
    return 1
  fi
  if [ -n "$errors" ]; then
    printf '%s\n' "$errors" >&2
    return 1
  fi
}

# Validates every entry file, enforces cross-file uniqueness, and prints the
# entries as a compact JSON array sorted by extensionId.
load_registry_entries() {
  local root=$1
  local files
  local f
  local dup_errors
  files=$(list_entry_files "$root") || return 1
  while IFS= read -r f; do
    assert_registry_entry "$f" || return 1
  done <<< "$files"
  if ! dup_errors=$(printf '%s\n' "$files" | concat_json_files | jq -s -r "$REGISTRY_ENTRY_DUP_JQ"); then
    echo 'Failed to parse registry entries.' >&2
    return 1
  fi
  if [ -n "$dup_errors" ]; then
    printf '%s\n' "$dup_errors" >&2
    return 1
  fi
  printf '%s\n' "$files" | concat_json_files | jq -s -c 'sort_by(.extensionId)'
}
