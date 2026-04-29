Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Entry {
  param(
    [hashtable]$Entry,
    [string]$FileName
  )

  if ($Entry.schemaVersion -ne 1) {
    throw "Unsupported schemaVersion in $FileName."
  }

  foreach ($requiredKey in @('extensionId', 'packageName', 'channel', 'status', 'featured')) {
    if (-not $Entry.ContainsKey($requiredKey)) {
      throw "Missing required key '$requiredKey' in $FileName."
    }
  }

  if ([string]::IsNullOrWhiteSpace($Entry.extensionId)) {
    throw "extensionId must be a non-empty string in $FileName."
  }

  if ([string]::IsNullOrWhiteSpace($Entry.packageName)) {
    throw "packageName must be a non-empty string in $FileName."
  }

  $allowedChannels = @('stable', 'preview', 'experimental')
  if ($Entry.channel -notin $allowedChannels) {
    throw "Invalid channel '$($Entry.channel)' in $FileName. Allowed values: $($allowedChannels -join ', ')."
  }

  $allowedStatuses = @('listed', 'hidden', 'deprecated', 'blocked')
  if ($Entry.status -notin $allowedStatuses) {
    throw "Invalid status '$($Entry.status)' in $FileName. Allowed values: $($allowedStatuses -join ', ')."
  }

  if ($Entry.featured -isnot [bool]) {
    throw "featured must be a boolean in $FileName."
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$entriesDir = Join-Path $repoRoot 'registry\extensions'
$indexPath = Join-Path $repoRoot 'registry\index.json'

$entryFiles = @(Get-ChildItem -Path $entriesDir -Filter '*.json' | Sort-Object Name)
if ($entryFiles.Count -eq 0) {
  throw 'No registry entry files found under registry/extensions/.'
}

$seenExtensionIds = @{}
$seenPackageNames = @{}
$items = New-Object System.Collections.Generic.List[object]

foreach ($entryFile in $entryFiles) {
  $entry = Get-Content -Raw -Path $entryFile.FullName | ConvertFrom-Json -AsHashtable
  Assert-Entry -Entry $entry -FileName $entryFile.Name

  if ($seenExtensionIds.ContainsKey($entry.extensionId)) {
    throw "Duplicate extensionId '$($entry.extensionId)' found in $($entryFile.Name) and $($seenExtensionIds[$entry.extensionId])."
  }

  if ($seenPackageNames.ContainsKey($entry.packageName)) {
    throw "Duplicate packageName '$($entry.packageName)' found in $($entryFile.Name) and $($seenPackageNames[$entry.packageName])."
  }

  $seenExtensionIds[$entry.extensionId] = $entryFile.Name
  $seenPackageNames[$entry.packageName] = $entryFile.Name

  $items.Add([ordered]@{
    extensionId = $entry.extensionId
    packageName = $entry.packageName
    channel = $entry.channel
    status = $entry.status
    featured = [bool]$entry.featured
  })
}

$sortedItems = $items | Sort-Object extensionId

$index = [ordered]@{
  '$schema' = '../schemas/marketplace-index.schema.json'
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  items = @($sortedItems)
}

$json = $index | ConvertTo-Json -Depth 5
Set-Content -Path $indexPath -Value ($json + [Environment]::NewLine)