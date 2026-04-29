Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'build-catalog.ps1')
& (Join-Path $PSScriptRoot 'validate-registry.ps1')