Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'registry-common.ps1')

$repoRoot = Get-RegistryRoot
$catalogPath = Join-Path $repoRoot 'registry\catalog.json'
$extensionsDir = Get-RegistryExtensionsRoot -RepoRoot $repoRoot
$items = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $extensionsDir -Recurse -Filter 'detail.json' -File | Remove-Item -Force

foreach ($entry in @(Get-RegistryEntries -RepoRoot $repoRoot)) {
  $readmePath = Get-RegistryReadmePath -RepoRoot $repoRoot -ExtensionId $entry.extensionId
  if (-not (Test-Path -Path $readmePath)) {
    throw "Missing README.md for extensionId '$($entry.extensionId)' at '$readmePath'."
  }

  $registryDocument = Get-PackageRegistryDocument -PackageName $entry.packageName
  $versionsObject = Get-ObjectPropertyValue -Object $registryDocument -PropertyName 'versions'
  $timeObject = Get-ObjectPropertyValue -Object $registryDocument -PropertyName 'time'
  $detailVersions = New-Object System.Collections.Generic.List[object]

  foreach ($entryVersion in @($entry.versions)) {
    $version = [string]$entryVersion.version
    $manifest = Get-ObjectPropertyValue -Object $versionsObject -PropertyName $version
    if ($null -eq $manifest) {
      throw "Version '$version' was not found in npm metadata for $($entry.packageName)."
    }

    $spiritExtension = Get-ObjectPropertyValue -Object $manifest -PropertyName 'spiritExtension'
    if ($null -eq $spiritExtension) {
      throw "Package $($entry.packageName)@$version is missing package.json spiritExtension metadata."
    }

    $displayName = [string](Get-ObjectPropertyValue -Object $spiritExtension -PropertyName 'displayName')
    if ([string]::IsNullOrWhiteSpace($displayName)) {
      throw "Package $($entry.packageName)@$version is missing spiritExtension.displayName."
    }

    $supportedHosts = @()
    $supportedHostsValue = Get-ObjectPropertyValue -Object $spiritExtension -PropertyName 'supportedHosts'
    if ($null -ne $supportedHostsValue) {
      $supportedHosts = @($supportedHostsValue | ForEach-Object { [string]$_ })
    }

    $requestedCapabilities = @()
    $requestedCapabilitiesValue = Get-ObjectPropertyValue -Object $spiritExtension -PropertyName 'requestedCapabilities'
    if ($null -ne $requestedCapabilitiesValue) {
      $requestedCapabilities = @($requestedCapabilitiesValue | ForEach-Object { [string]$_ })
    }

    $iconPathValue = Get-ObjectPropertyValue -Object $spiritExtension -PropertyName 'icon'
    $iconPath = if ($null -ne $iconPathValue) { [string]$iconPathValue } else { $null }

    $publishedAt = $null
    $publishedAtValue = Get-ObjectPropertyValue -Object $timeObject -PropertyName $version
    if ($null -ne $publishedAtValue) {
      if ($publishedAtValue -is [datetime]) {
        $publishedAt = $publishedAtValue.ToUniversalTime().ToString('o')
      } else {
        $publishedAt = [string]$publishedAtValue
      }
    }

    $dist = Get-ObjectPropertyValue -Object $manifest -PropertyName 'dist'
    $descriptionValue = Get-ObjectPropertyValue -Object $manifest -PropertyName 'description'
    $homepageValue = Get-ObjectPropertyValue -Object $manifest -PropertyName 'homepage'
    $keywordsValue = Get-ObjectPropertyValue -Object $manifest -PropertyName 'keywords'
    $authorValue = Get-ObjectPropertyValue -Object $manifest -PropertyName 'author'
    $repositoryValue = Get-ObjectPropertyValue -Object $manifest -PropertyName 'repository'

    $detailVersion = [ordered]@{
      version = $version
      channel = [string]$entryVersion.channel
      reviewStatus = [string]$entryVersion.reviewStatus
      displayName = $displayName
      description = if ($null -ne $descriptionValue) { [string]$descriptionValue } else { '' }
      author = ConvertTo-AuthorString -Author $authorValue
      homepageUrl = if ($null -ne $homepageValue) { [string]$homepageValue } else { $null }
      repositoryUrl = Get-RepositoryUrl -Repository $repositoryValue
      keywords = if ($null -ne $keywordsValue) { @($keywordsValue | ForEach-Object { [string]$_ }) } else { @() }
      supportedHosts = @($supportedHosts)
      requestedCapabilities = @($requestedCapabilities)
      iconUrl = New-IconUrl -PackageName $entry.packageName -Version $version -IconPath $iconPath
      publishedAt = $publishedAt
      tarballUrl = if ($null -ne $dist -and (Get-ObjectPropertyValue -Object $dist -PropertyName 'tarball')) { [string](Get-ObjectPropertyValue -Object $dist -PropertyName 'tarball') } else { $null }
      integrity = if ($null -ne $dist -and (Get-ObjectPropertyValue -Object $dist -PropertyName 'integrity')) { [string](Get-ObjectPropertyValue -Object $dist -PropertyName 'integrity') } else { $null }
      shasum = if ($null -ne $dist -and (Get-ObjectPropertyValue -Object $dist -PropertyName 'shasum')) { [string](Get-ObjectPropertyValue -Object $dist -PropertyName 'shasum') } else { $null }
    }

    $changelog = Get-ObjectPropertyValue -Object $entryVersion -PropertyName 'changelog'
    if ($null -ne $changelog) {
      $detailVersion.changelog = [ordered]@{
        summary = [string]$changelog.summary
        body = [string]$changelog.body
      }
    }

    foreach ($optionalField in @('author', 'homepageUrl', 'repositoryUrl', 'iconUrl', 'publishedAt', 'tarballUrl', 'integrity', 'shasum')) {
      if ($null -eq $detailVersion[$optionalField] -or [string]::IsNullOrWhiteSpace([string]$detailVersion[$optionalField])) {
        $detailVersion.Remove($optionalField)
      }
    }

    if ($detailVersion.keywords.Count -eq 0) {
      $detailVersion.Remove('keywords')
    }

    $detailVersions.Add($detailVersion)
  }

  $defaultEntryVersion = Get-EntryDefaultVersionItem -Entry $entry
  $defaultDetailVersion = $null
  foreach ($detailVersion in @($detailVersions.ToArray())) {
    if ([string]$detailVersion.version -ceq [string]$entry.defaultVersion) {
      $defaultDetailVersion = $detailVersion
      break
    }
  }

  if ($null -eq $defaultDetailVersion) {
    throw "defaultVersion '$($entry.defaultVersion)' was not found in generated detail versions for extensionId '$($entry.extensionId)'."
  }

  $detailRelativePath = Get-RegistryDetailRelativePath -ExtensionId $entry.extensionId
  $catalogItem = [ordered]@{
    extensionId = $entry.extensionId
    packageName = $entry.packageName
    status = $entry.status
    featured = [bool]$entry.featured
    defaultVersion = [string]$entry.defaultVersion
    defaultChannel = [string]$defaultEntryVersion.channel
    defaultReviewStatus = [string]$entry.defaultReviewStatus
    detailPath = $detailRelativePath
    displayName = [string]$defaultDetailVersion.displayName
    description = [string]$defaultDetailVersion.description
    author = Get-ObjectPropertyValue -Object $defaultDetailVersion -PropertyName 'author'
    homepageUrl = Get-ObjectPropertyValue -Object $defaultDetailVersion -PropertyName 'homepageUrl'
    repositoryUrl = Get-ObjectPropertyValue -Object $defaultDetailVersion -PropertyName 'repositoryUrl'
    keywords = Get-ObjectPropertyValue -Object $defaultDetailVersion -PropertyName 'keywords'
    supportedHosts = @($defaultDetailVersion.supportedHosts)
    requestedCapabilities = @($defaultDetailVersion.requestedCapabilities)
    iconUrl = Get-ObjectPropertyValue -Object $defaultDetailVersion -PropertyName 'iconUrl'
  }

  foreach ($optionalField in @('author', 'homepageUrl', 'repositoryUrl', 'iconUrl')) {
    if ($null -eq $catalogItem[$optionalField] -or [string]::IsNullOrWhiteSpace([string]$catalogItem[$optionalField])) {
      $catalogItem.Remove($optionalField)
    }
  }

  if ($null -eq $catalogItem.keywords -or $catalogItem.keywords.Count -eq 0) {
    $catalogItem.Remove('keywords')
  }

  $detailItem = [ordered]@{
     '$schema' = '../../../schemas/marketplace-detail.schema.json'
    schemaVersion = 1
    extensionId = $entry.extensionId
    packageName = $entry.packageName
    status = $entry.status
    featured = [bool]$entry.featured
    defaultVersion = [string]$entry.defaultVersion
    defaultReviewStatus = [string]$entry.defaultReviewStatus
    readmePath = (Get-RegistryReadmeRelativePath -ExtensionId $entry.extensionId)
    versions = @($detailVersions.ToArray())
  }

  $detailJson = $detailItem | ConvertTo-Json -Depth 8
  New-Item -ItemType Directory -Path (Split-Path -Parent (Get-RegistryDetailPath -RepoRoot $repoRoot -ExtensionId $entry.extensionId)) -Force | Out-Null
  Set-Content -Path (Get-RegistryDetailPath -RepoRoot $repoRoot -ExtensionId $entry.extensionId) -Value ($detailJson + [Environment]::NewLine)

  $items.Add($catalogItem)
}

$catalog = [ordered]@{
  '$schema' = '../schemas/marketplace-catalog.schema.json'
  schemaVersion = 1
  items = @($items | Sort-Object extensionId)
}

$json = $catalog | ConvertTo-Json -Depth 6
Set-Content -Path $catalogPath -Value ($json + [Environment]::NewLine)