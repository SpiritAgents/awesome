Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'registry-common.ps1')

$repoRoot = Get-RegistryRoot
$entries = @(Get-RegistryEntries -RepoRoot $repoRoot)
$catalogPath = Join-Path $repoRoot 'registry\catalog.json'

if (-not (Test-Path -Path $catalogPath)) {
  throw 'registry/catalog.json is missing. Run ./scripts/build-catalog.ps1 to regenerate it.'
}

$catalog = Get-Content -Raw -Path $catalogPath | ConvertFrom-Json -AsHashtable
if ($catalog.schemaVersion -ne 1) {
  throw 'registry/catalog.json has an unsupported schemaVersion.'
}

if (-not $catalog.ContainsKey('items')) {
  throw 'registry/catalog.json is missing the items array.'
}

$catalogItems = @($catalog.items)
if ($catalogItems.Count -ne $entries.Count) {
  throw "registry/catalog.json item count ($($catalogItems.Count)) does not match registry/extensions item count ($($entries.Count))."
}

$seenCatalogExtensionIds = @{}

foreach ($catalogItem in $catalogItems) {
  foreach ($requiredKey in @('extensionId', 'packageName', 'channel', 'status', 'featured', 'displayName', 'description', 'supportedHosts', 'requestedCapabilities')) {
    if (-not $catalogItem.ContainsKey($requiredKey)) {
      throw "registry/catalog.json is missing required key '$requiredKey' on one or more items."
    }
  }

  if ($seenCatalogExtensionIds.ContainsKey($catalogItem.extensionId)) {
    throw "Duplicate extensionId '$($catalogItem.extensionId)' found in registry/catalog.json."
  }

  $seenCatalogExtensionIds[$catalogItem.extensionId] = $true
}

foreach ($entry in $entries) {
  $matchingItem = $catalogItems | Where-Object { $_.extensionId -eq $entry.extensionId }
  if ($null -eq $matchingItem) {
    throw "registry/catalog.json is missing extensionId '$($entry.extensionId)'."
  }

  if (@($matchingItem).Count -ne 1) {
    throw "registry/catalog.json contains multiple items for extensionId '$($entry.extensionId)'."
  }

  $catalogItem = @($matchingItem)[0]

  foreach ($field in @('packageName', 'channel', 'status', 'featured')) {
    if ($catalogItem[$field] -cne $entry[$field]) {
      throw "registry/catalog.json is out of sync for extensionId '$($entry.extensionId)' field '$field'."
    }
  }
}