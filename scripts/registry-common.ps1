Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RegistryRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..'))
}

function Get-RegistryExtensionsRoot {
  param(
    [string]$RepoRoot
  )

  return (Join-Path $RepoRoot 'registry\extensions')
}

function Get-RegistryEntryFiles {
  param(
    [string]$RepoRoot
  )

  $entriesDir = Get-RegistryExtensionsRoot -RepoRoot $RepoRoot
  $entryFiles = @(Get-ChildItem -Path $entriesDir -Recurse -Filter 'entry.json' | Sort-Object FullName)
  if ($entryFiles.Count -eq 0) {
    throw 'No registry entry files found under registry/extensions/**/entry.json.'
  }

  return $entryFiles
}

function Assert-RegistryEntry {
  param(
    [hashtable]$Entry,
    [string]$FileName
  )

  if ($Entry.schemaVersion -ne 1) {
    throw "Unsupported schemaVersion in $FileName."
  }

  foreach ($requiredKey in @('extensionId', 'packageName', 'status', 'featured', 'defaultVersion', 'versions')) {
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

  if ([string]::IsNullOrWhiteSpace([string]$Entry.defaultVersion)) {
    throw "defaultVersion must be a non-empty string in $FileName."
  }

  $allowedStatuses = @('listed', 'hidden', 'deprecated', 'blocked')
  if ($Entry.status -notin $allowedStatuses) {
    throw "Invalid status '$($Entry.status)' in $FileName. Allowed values: $($allowedStatuses -join ', ')."
  }

  if ($Entry.featured -isnot [bool]) {
    throw "featured must be a boolean in $FileName."
  }

  $versions = @($Entry.versions)
  if ($versions.Count -eq 0) {
    throw "versions must contain at least one item in $FileName."
  }

  $seenVersions = @{}
  $allowedChannels = @('stable', 'preview', 'experimental')
  $allowedReviewStatuses = @('unverified', 'verified', 'revoked')

  foreach ($versionItem in $versions) {
    foreach ($requiredKey in @('version', 'channel', 'reviewStatus')) {
      if (-not $versionItem.ContainsKey($requiredKey)) {
        throw "Missing required version key '$requiredKey' in $FileName."
      }
    }

    if ([string]::IsNullOrWhiteSpace([string]$versionItem.version)) {
      throw "version must be a non-empty string in $FileName."
    }

    if ($seenVersions.ContainsKey([string]$versionItem.version)) {
      throw "Duplicate version '$($versionItem.version)' found in $FileName."
    }

    if ($versionItem.channel -notin $allowedChannels) {
      throw "Invalid channel '$($versionItem.channel)' in $FileName. Allowed values: $($allowedChannels -join ', ')."
    }

    if ($versionItem.reviewStatus -notin $allowedReviewStatuses) {
      throw "Invalid reviewStatus '$($versionItem.reviewStatus)' in $FileName. Allowed values: $($allowedReviewStatuses -join ', ')."
    }

    $changelog = Get-ObjectPropertyValue -Object $versionItem -PropertyName 'changelog'
    if ($null -ne $changelog) {
      foreach ($requiredKey in @('summary', 'body')) {
        if (-not $changelog.ContainsKey($requiredKey)) {
          throw "Missing required changelog key '$requiredKey' in $FileName."
        }
      }

      if ([string]::IsNullOrWhiteSpace([string]$changelog.summary)) {
        throw "changelog.summary must be a non-empty string in $FileName."
      }

      if ([string]::IsNullOrWhiteSpace([string]$changelog.body)) {
        throw "changelog.body must be a non-empty string in $FileName."
      }
    }

    $seenVersions[[string]$versionItem.version] = $true
  }

  if (-not $seenVersions.ContainsKey([string]$Entry.defaultVersion)) {
    throw "defaultVersion '$($Entry.defaultVersion)' was not found in the versions list for $FileName."
  }
}

function Get-RegistryEntries {
  param(
    [string]$RepoRoot
  )

  $seenExtensionIds = @{}
  $seenPackageNames = @{}
  $entries = New-Object System.Collections.Generic.List[hashtable]

  foreach ($entryFile in (Get-RegistryEntryFiles -RepoRoot $RepoRoot)) {
    $entry = Get-Content -Raw -Path $entryFile.FullName | ConvertFrom-Json -AsHashtable
    Assert-RegistryEntry -Entry $entry -FileName $entryFile.FullName

    if ($seenExtensionIds.ContainsKey($entry.extensionId)) {
      throw "Duplicate extensionId '$($entry.extensionId)' found in $($entryFile.FullName) and $($seenExtensionIds[$entry.extensionId])."
    }

    if ($seenPackageNames.ContainsKey($entry.packageName)) {
      throw "Duplicate packageName '$($entry.packageName)' found in $($entryFile.FullName) and $($seenPackageNames[$entry.packageName])."
    }

    $seenExtensionIds[$entry.extensionId] = $entryFile.FullName
    $seenPackageNames[$entry.packageName] = $entryFile.FullName
    $entries.Add($entry)
  }

  return @($entries | Sort-Object extensionId)
}

function Get-PackageRegistryDocument {
  param(
    [string]$PackageName
  )

  $escapedPackageName = [Uri]::EscapeDataString($PackageName)
  $uri = "https://registry.npmjs.org/$escapedPackageName"
  return Invoke-RestMethod -Uri $uri -Method Get
}

function Get-ObjectPropertyValue {
  param(
    $Object,
    [string]$PropertyName
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($PropertyName)) {
      return $Object[$PropertyName]
    }

    return $null
  }

  $property = $Object.PSObject.Properties[$PropertyName]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function ConvertTo-AuthorString {
  param(
    $Author
  )

  if ($null -eq $Author) {
    return $null
  }

  if ($Author -is [string]) {
    return $Author
  }

  if ($Author.name) {
    return [string]$Author.name
  }

  return $null
}

function Get-RepositoryUrl {
  param(
    $Repository
  )

  $url = $null
  if ($null -eq $Repository) {
    return $null
  }

  if ($Repository -is [string]) {
    $url = $Repository
  } elseif ($Repository.url) {
    $url = [string]$Repository.url
  }

  if ([string]::IsNullOrWhiteSpace($url)) {
    return $null
  }

  $url = $url -replace '^git\+', ''
  $url = $url -replace '^git://github\.com/', 'https://github.com/'
  $url = $url -replace '\.git$', ''
  return $url
}

function New-IconUrl {
  param(
    [string]$PackageName,
    [string]$Version,
    [string]$IconPath
  )

  if ([string]::IsNullOrWhiteSpace($IconPath)) {
    return $null
  }

  $normalizedPath = $IconPath.TrimStart('./').Replace('\', '/')
  return "https://cdn.jsdelivr.net/npm/$PackageName@$Version/$normalizedPath"
}

function Get-RegistryEntryPath {
  param(
    [string]$RepoRoot,
    [string]$ExtensionId
  )

  return (Join-Path $RepoRoot (Join-Path 'registry\extensions' (Join-Path $ExtensionId 'entry.json')))
}

function Get-RegistryDetailRelativePath {
  param(
    [string]$ExtensionId
  )

  return "extensions/$ExtensionId/detail.json"
}

function Get-RegistryDetailPath {
  param(
    [string]$RepoRoot,
    [string]$ExtensionId
  )

  return (Join-Path $RepoRoot (Join-Path 'registry\extensions' (Join-Path $ExtensionId 'detail.json')))
}

function Get-RegistryReadmeRelativePath {
  param(
    [string]$ExtensionId
  )

  return "extensions/$ExtensionId/README.md"
}

function Get-RegistryReadmePath {
  param(
    [string]$RepoRoot,
    [string]$ExtensionId
  )

  return (Join-Path $RepoRoot (Join-Path 'registry\extensions' (Join-Path $ExtensionId 'README.md')))
}

function Get-EntryDefaultVersionItem {
  param(
    [hashtable]$Entry
  )

  foreach ($versionItem in @($Entry.versions)) {
    if ([string]$versionItem.version -ceq [string]$Entry.defaultVersion) {
      return $versionItem
    }
  }

  throw "defaultVersion '$($Entry.defaultVersion)' was not found for extension '$($Entry.extensionId)'."
}
