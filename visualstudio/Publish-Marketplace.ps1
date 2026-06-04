param(
    [string] $VsixPath = (Join-Path $PSScriptRoot "..\artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.27.vsix"),
    [string] $PublishManifest = (Join-Path $PSScriptRoot "marketplace.publish.json"),
    [string] $PublisherName = "vwzhang",
    [string] $PersonalAccessToken = $env:VS_MARKETPLACE_PAT,
    [string] $VsixPublisherPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

if (-not $PersonalAccessToken) {
    throw "Set VS_MARKETPLACE_PAT or pass -PersonalAccessToken. Do not commit or print the token."
}

if (-not (Test-Path -LiteralPath $VsixPath)) {
    throw "VSIX package not found: $VsixPath. Run visualstudio\Build-Vsix.ps1 first."
}

if (-not (Test-Path -LiteralPath $PublishManifest)) {
    throw "Publish manifest not found: $PublishManifest"
}

if (-not $VsixPublisherPath) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe was not found. Install Visual Studio SDK or pass -VsixPublisherPath."
    }

    $installPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VSSDK -property installationPath
    if (-not $installPath) {
        throw "Visual Studio SDK was not found. Install the Visual Studio extension development workload."
    }

    $VsixPublisherPath = Join-Path $installPath "VSSDK\VisualStudioIntegration\Tools\Bin\VsixPublisher.exe"
}

if (-not (Test-Path -LiteralPath $VsixPublisherPath)) {
    throw "VsixPublisher.exe was not found: $VsixPublisherPath"
}

& $VsixPublisherPath publish `
    -payload (Resolve-FullPath $VsixPath) `
    -publishManifest (Resolve-FullPath $PublishManifest) `
    -personalAccessToken $PersonalAccessToken

Write-Host "Published VSIX with publisher '$PublisherName'."
