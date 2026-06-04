param(
    [string] $InstanceId = "",
    [string] $ExtensionId = "Vwzhang.EnhancedAspireStarter.VisualStudio",
    [string] $TemplateZipName = "EnhancedAspireStarter.zip"
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Remove-DirectoryIfSafe([string] $Path, [string] $AllowedRoot) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedPath = Resolve-FullPath $Path
    $resolvedRoot = (Resolve-FullPath $AllowedRoot).TrimEnd("\", "/") + "\"

    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove '$resolvedPath' because it is outside '$resolvedRoot'."
    }

    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    Write-Host "Removed $resolvedPath"
}

function Get-VisualStudioInstanceIds {
    $visualStudioRoot = Join-Path $env:LOCALAPPDATA "Microsoft\VisualStudio"

    if (-not (Test-Path -LiteralPath $visualStudioRoot)) {
        return @()
    }

    Get-ChildItem -LiteralPath $visualStudioRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+_[A-Za-z0-9]+$' } |
        Select-Object -ExpandProperty Name
}

$runningVisualStudio = Get-Process devenv -ErrorAction SilentlyContinue
if ($runningVisualStudio) {
    throw "Close Visual Studio before clearing template caches."
}

$instanceIds = if ([string]::IsNullOrWhiteSpace($InstanceId)) {
    @(Get-VisualStudioInstanceIds)
}
else {
    @($InstanceId)
}

if ($instanceIds.Count -eq 0) {
    throw "No Visual Studio instance folders were found under $env:LOCALAPPDATA\Microsoft\VisualStudio."
}

$visualStudioRoot = Resolve-FullPath (Join-Path $env:LOCALAPPDATA "Microsoft\VisualStudio")

foreach ($id in $instanceIds) {
    $instanceRoot = Join-Path $visualStudioRoot $id

    if (-not (Test-Path -LiteralPath $instanceRoot)) {
        Write-Warning "Visual Studio instance folder was not found: $instanceRoot"
        continue
    }

    Write-Host "Cleaning Visual Studio instance $id"

    $extensionsRoot = Join-Path $instanceRoot "Extensions"
    if (Test-Path -LiteralPath $extensionsRoot) {
        foreach ($extensionDirectory in Get-ChildItem -LiteralPath $extensionsRoot -Directory) {
            $manifestPath = Join-Path $extensionDirectory.FullName "extension.vsixmanifest"
            $catalogPath = Join-Path $extensionDirectory.FullName "catalog.json"
            $matchesExtension = $false

            if (Test-Path -LiteralPath $manifestPath) {
                $matchesExtension = (Get-Content -LiteralPath $manifestPath -Raw).Contains($ExtensionId)
            }

            if (-not $matchesExtension -and (Test-Path -LiteralPath $catalogPath)) {
                $matchesExtension = (Get-Content -LiteralPath $catalogPath -Raw).Contains($ExtensionId)
            }

            if ($matchesExtension) {
                Remove-DirectoryIfSafe $extensionDirectory.FullName $extensionsRoot
            }
        }
    }

    $vtcRoot = Join-Path $instanceRoot "VTC"
    if (Test-Path -LiteralPath $vtcRoot) {
        foreach ($cacheDirectory in Get-ChildItem -LiteralPath $vtcRoot -Directory) {
            $hasTemplateZip = Get-ChildItem -LiteralPath $cacheDirectory.FullName -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $TemplateZipName } |
                Select-Object -First 1

            if ($hasTemplateZip) {
                Remove-DirectoryIfSafe $cacheDirectory.FullName $vtcRoot
            }
        }
    }

    $templateEngineHostRoot = Join-Path $instanceRoot "TemplateEngineHost"
    if (Test-Path -LiteralPath $templateEngineHostRoot) {
        Remove-DirectoryIfSafe $templateEngineHostRoot $instanceRoot
    }

    foreach ($cacheFile in Get-ChildItem -LiteralPath $instanceRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "NpdProjectTemplateCache*" -or $_.Name -eq "InstalledTemplates.json" }) {
        $resolvedPath = Resolve-FullPath $cacheFile.FullName
        $resolvedRoot = (Resolve-FullPath $instanceRoot).TrimEnd("\", "/") + "\"

        if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove '$resolvedPath' because it is outside '$resolvedRoot'."
        }

        Remove-Item -LiteralPath $resolvedPath -Force
        Write-Host "Removed $resolvedPath"
    }

    foreach ($cacheDirectory in Get-ChildItem -LiteralPath $instanceRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "ProjectTemplatesCache_*" }) {
        Remove-DirectoryIfSafe $cacheDirectory.FullName $instanceRoot
    }
}

Write-Host "Visual Studio template cache cleanup completed."
