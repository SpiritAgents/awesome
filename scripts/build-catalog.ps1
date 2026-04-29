Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'registry-common.ps1')

$repoRoot = Get-RegistryRoot
$catalogPath = Join-Path $repoRoot 'registry\catalog.json'
$items = New-Object System.Collections.Generic.List[object]

foreach ($entry in @(Get-RegistryEntries -RepoRoot $repoRoot)) {
  $registryDocument = Get-PackageRegistryDocument -PackageName $entry.packageName
  $distTagsObject = Get-ObjectPropertyValue -Object $registryDocument -PropertyName 'dist-tags'
  if ($null -eq $distTagsObject) {
    throw "Package $($entry.packageName) is missing npm dist-tags metadata."
  }

  $distTags = @{}
  foreach ($property in $distTagsObject.PSObject.Properties) {
    $distTags[$property.Name] = [string]$property.Value
  }

  $resolvedVersion = Get-PreferredDistTagValue -DistTags $distTags -Channel $entry.channel
  $version = $resolvedVersion.version
  $distTag = $resolvedVersion.distTag
  $versionsObject = Get-ObjectPropertyValue -Object $registryDocument -PropertyName 'versions'
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
  $timeObject = Get-ObjectPropertyValue -Object $registryDocument -PropertyName 'time'
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

  $catalogItem = [ordered]@{
    extensionId = $entry.extensionId
    packageName = $entry.packageName
    channel = $entry.channel
    status = $entry.status
    featured = [bool]$entry.featured
    distTag = $distTag
    version = [string]$version
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

  foreach ($optionalField in @('author', 'homepageUrl', 'repositoryUrl', 'iconUrl', 'publishedAt', 'tarballUrl', 'integrity', 'shasum')) {
    if ($null -eq $catalogItem[$optionalField] -or [string]::IsNullOrWhiteSpace([string]$catalogItem[$optionalField])) {
      $catalogItem.Remove($optionalField)
    }
  }

  if ($catalogItem.keywords.Count -eq 0) {
    $catalogItem.Remove('keywords')
  }

  $items.Add($catalogItem)
}

$catalog = [ordered]@{
  '$schema' = '../schemas/marketplace-catalog.schema.json'
  schemaVersion = 1
  items = @($items | Sort-Object extensionId)
}

$json = $catalog | ConvertTo-Json -Depth 6
Set-Content -Path $catalogPath -Value ($json + [Environment]::NewLine)