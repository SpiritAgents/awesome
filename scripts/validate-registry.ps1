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

$detailFiles = @(Get-ChildItem -Path (Get-RegistryExtensionsRoot -RepoRoot $repoRoot) -Recurse -Filter 'detail.json' -File)
if ($detailFiles.Count -ne $entries.Count) {
  throw "registry/extensions/**/detail.json file count ($($detailFiles.Count)) does not match registry entry count ($($entries.Count))."
}

$seenCatalogExtensionIds = @{}

foreach ($catalogItem in $catalogItems) {
  foreach ($requiredKey in @('extensionId', 'packageName', 'status', 'featured', 'defaultVersion', 'defaultChannel', 'defaultReviewStatus', 'detailPath', 'displayName', 'description', 'supportedHosts', 'requestedCapabilities')) {
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
  $readmeFilePath = Get-RegistryReadmePath -RepoRoot $repoRoot -ExtensionId $entry.extensionId
  if (-not (Test-Path -Path $readmeFilePath)) {
    throw "registry/extensions/$($entry.extensionId)/README.md is missing."
  }

  $matchingItem = @($catalogItems | Where-Object { $_.extensionId -eq $entry.extensionId })
  if ($matchingItem.Count -eq 0) {
    throw "registry/catalog.json is missing extensionId '$($entry.extensionId)'."
  }

  if ($matchingItem.Count -ne 1) {
    throw "registry/catalog.json contains multiple items for extensionId '$($entry.extensionId)'."
  }

  $catalogItem = $matchingItem[0]

  foreach ($field in @('packageName', 'status', 'featured', 'defaultVersion')) {
    if ($catalogItem[$field] -cne $entry[$field]) {
      throw "registry/catalog.json is out of sync for extensionId '$($entry.extensionId)' field '$field'."
    }
  }

  $defaultEntryVersion = Get-EntryDefaultVersionItem -Entry $entry
  foreach ($field in @('channel', 'reviewStatus')) {
    $catalogField = if ($field -eq 'channel') { 'defaultChannel' } else { 'defaultReviewStatus' }
    if ($catalogItem[$catalogField] -cne $defaultEntryVersion[$field]) {
      throw "registry/catalog.json is out of sync for extensionId '$($entry.extensionId)' field '$catalogField'."
    }
  }

  $expectedDetailPath = Get-RegistryDetailRelativePath -ExtensionId $entry.extensionId
  if ($catalogItem.detailPath -cne $expectedDetailPath) {
    throw "registry/catalog.json has an unexpected detailPath for extensionId '$($entry.extensionId)'."
  }

  $detailFilePath = Get-RegistryDetailPath -RepoRoot $repoRoot -ExtensionId $entry.extensionId
  if (-not (Test-Path -Path $detailFilePath)) {
    throw "Missing detail artifact for extensionId '$($entry.extensionId)'."
  }

  $detail = Get-Content -Raw -Path $detailFilePath | ConvertFrom-Json -AsHashtable
  foreach ($requiredKey in @('schemaVersion', 'extensionId', 'packageName', 'status', 'featured', 'defaultVersion', 'readmePath', 'versions')) {
    if (-not $detail.ContainsKey($requiredKey)) {
      throw "registry/extensions/$($entry.extensionId)/detail.json is missing required key '$requiredKey'."
    }
  }

  foreach ($field in @('extensionId', 'packageName', 'status', 'featured', 'defaultVersion')) {
    if ($detail[$field] -cne $entry[$field]) {
      throw "registry/extensions/$($entry.extensionId)/detail.json is out of sync for field '$field'."
    }
  }

  $expectedReadmePath = Get-RegistryReadmeRelativePath -ExtensionId $entry.extensionId
  if ($detail.readmePath -cne $expectedReadmePath) {
    throw "registry/extensions/$($entry.extensionId)/detail.json has an unexpected readmePath."
  }

  $entryVersions = @($entry.versions)
  $detailVersions = @($detail.versions)
  if ($detailVersions.Count -ne $entryVersions.Count) {
    throw "registry/extensions/$($entry.extensionId)/detail.json version count is out of sync."
  }

  $defaultDetailVersion = $null
  foreach ($detailVersion in $detailVersions) {
    if ([string]$detailVersion.version -ceq [string]$entry.defaultVersion) {
      $defaultDetailVersion = $detailVersion
      break
    }
  }

  if ($null -eq $defaultDetailVersion) {
    throw "registry/extensions/$($entry.extensionId)/detail.json is missing defaultVersion '$($entry.defaultVersion)'."
  }

  foreach ($field in @('displayName', 'description', 'supportedHosts', 'requestedCapabilities')) {
    if (-not $defaultDetailVersion.ContainsKey($field)) {
      throw "registry/extensions/$($entry.extensionId)/detail.json default version is missing '$field'."
    }

    $catalogValue = if ($catalogItem[$field] -is [array]) { @($catalogItem[$field]) -join "`n" } else { [string]$catalogItem[$field] }
    $detailValue = if ($defaultDetailVersion[$field] -is [array]) { @($defaultDetailVersion[$field]) -join "`n" } else { [string]$defaultDetailVersion[$field] }
    if ($catalogValue -cne $detailValue) {
      throw "registry/catalog.json is out of sync with detail artifact for extensionId '$($entry.extensionId)' field '$field'."
    }
  }

  foreach ($field in @('author', 'homepageUrl', 'repositoryUrl', 'iconUrl')) {
    $catalogHasField = $catalogItem.ContainsKey($field)
    $detailHasField = $defaultDetailVersion.ContainsKey($field)
    if ($catalogHasField -ne $detailHasField) {
      throw "registry/catalog.json optional field '$field' is out of sync with detail artifact for extensionId '$($entry.extensionId)'."
    }

    if ($catalogHasField -and $catalogItem[$field] -cne $defaultDetailVersion[$field]) {
      throw "registry/catalog.json optional field '$field' is out of sync with detail artifact for extensionId '$($entry.extensionId)'."
    }
  }

  $catalogHasKeywords = $catalogItem.ContainsKey('keywords')
  $detailHasKeywords = $defaultDetailVersion.ContainsKey('keywords')
  if ($catalogHasKeywords -ne $detailHasKeywords) {
    throw "registry/catalog.json keywords are out of sync with detail artifact for extensionId '$($entry.extensionId)'."
  }

  if ($catalogHasKeywords -and ((@($catalogItem.keywords) -join "`n") -cne (@($defaultDetailVersion.keywords) -join "`n"))) {
    throw "registry/catalog.json keywords are out of sync with detail artifact for extensionId '$($entry.extensionId)'."
  }

  foreach ($entryVersion in $entryVersions) {
    $matchingDetailVersions = @($detailVersions | Where-Object { $_.version -ceq $entryVersion.version })
    if ($matchingDetailVersions.Count -ne 1) {
      throw "registry/extensions/$($entry.extensionId)/detail.json has an invalid number of entries for version '$($entryVersion.version)'."
    }

    $detailVersion = $matchingDetailVersions[0]

    foreach ($requiredKey in @('version', 'channel', 'reviewStatus', 'displayName', 'description', 'supportedHosts', 'requestedCapabilities')) {
      if (-not $detailVersion.ContainsKey($requiredKey)) {
        throw "registry/extensions/$($entry.extensionId)/detail.json is missing required version key '$requiredKey' for version '$($entryVersion.version)'."
      }
    }

    foreach ($field in @('version', 'channel', 'reviewStatus')) {
      if ($detailVersion[$field] -cne $entryVersion[$field]) {
        throw "registry/extensions/$($entry.extensionId)/detail.json is out of sync for version '$($entryVersion.version)' field '$field'."
      }
    }

    $entryChangelog = Get-ObjectPropertyValue -Object $entryVersion -PropertyName 'changelog'
    $detailChangelog = Get-ObjectPropertyValue -Object $detailVersion -PropertyName 'changelog'
    if (($null -eq $entryChangelog) -ne ($null -eq $detailChangelog)) {
      throw "registry/extensions/$($entry.extensionId)/detail.json changelog presence is out of sync for version '$($entryVersion.version)'."
    }

    if ($null -ne $entryChangelog) {
      foreach ($field in @('summary', 'body')) {
        if ($detailChangelog[$field] -cne $entryChangelog[$field]) {
          throw "registry/extensions/$($entry.extensionId)/detail.json changelog field '$field' is out of sync for version '$($entryVersion.version)'."
        }
      }
    }
  }
}
