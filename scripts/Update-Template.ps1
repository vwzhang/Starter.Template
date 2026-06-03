param(
    [string] $SourceRepository = (Join-Path $PSScriptRoot "..\..\Starter"),
    [string] $TemplateVersion = "0.1.6",
    [string] $Configuration = "Release",
    [switch] $SkipSync
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Set-TextFile([string] $Path, [string] $Content) {
    [System.IO.File]::WriteAllText((Resolve-FullPath $Path), $Content, [System.Text.UTF8Encoding]::new($false))
}

function Update-TextFile([string] $Path, [scriptblock] $Update) {
    $resolvedPath = Resolve-FullPath $Path
    $content = [System.IO.File]::ReadAllText($resolvedPath)
    $updated = & $Update $content

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($resolvedPath, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}

$repoRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$templateRoot = Join-Path $repoRoot "templates\enhanced-aspire-starter"
$sourceRepositoryPath = Resolve-FullPath $SourceRepository

if (-not $SkipSync) {
    & (Join-Path $PSScriptRoot "Sync-TemplateSource.ps1") `
        -SourceRepository $sourceRepositoryPath `
        -TemplateContent $templateRoot `
        -TemplateVersion $TemplateVersion
}

$templateInfoPath = Join-Path $templateRoot "Starter.Shared\TemplateInfo.cs"
$templateInfo = @"
namespace Starter.Shared;

public static class TemplateInfo
{
    public const string Name = "Enhanced Aspire Template";
    public const string Version = "$TemplateVersion";
}
"@
Set-TextFile $templateInfoPath ($templateInfo + "`n")

Update-TextFile (Join-Path $repoRoot "EnhancedAspireStarter.Templates.csproj") {
    param($content)
    $content -replace '<PackageVersion>[^<]+</PackageVersion>', "<PackageVersion>$TemplateVersion</PackageVersion>"
}

Update-TextFile (Join-Path $repoRoot "visualstudio\Build-Vsix.ps1") {
    param($content)
    $content -replace '\[string\] \$Version = "[^"]+"', "[string] `$Version = ""$TemplateVersion"""
}

Update-TextFile (Join-Path $repoRoot "visualstudio\Publish-Marketplace.ps1") {
    param($content)
    $content -replace 'EnhancedAspireStarter\.VisualStudio\.[0-9]+\.[0-9]+\.[0-9]+\.vsix', "EnhancedAspireStarter.VisualStudio.$TemplateVersion.vsix"
}

Update-TextFile (Join-Path $repoRoot "README.md") {
    param($content)
    $content = $content -replace 'Vwzhang\.EnhancedAspireStarter\.Templates\.[0-9]+\.[0-9]+\.[0-9]+\.nupkg', "Vwzhang.EnhancedAspireStarter.Templates.$TemplateVersion.nupkg"
    $content -replace 'EnhancedAspireStarter\.VisualStudio\.[0-9]+\.[0-9]+\.[0-9]+\.vsix', "EnhancedAspireStarter.VisualStudio.$TemplateVersion.vsix"
}

Update-TextFile (Join-Path $repoRoot "visualstudio\README.md") {
    param($content)
    $content -replace 'EnhancedAspireStarter\.VisualStudio\.[0-9]+\.[0-9]+\.[0-9]+\.vsix', "EnhancedAspireStarter.VisualStudio.$TemplateVersion.vsix"
}

Update-TextFile (Join-Path $templateRoot "README.md") {
    param($content)
    $versionLine = "Template version: ``$TemplateVersion``. The same value is available in ``Starter.Shared.TemplateInfo.Version``."
    $versionPattern = 'Template version: `[^`]+`\. The same value is available in `Starter\.Shared\.TemplateInfo\.Version`\.'

    if ($content -match $versionPattern) {
        return [regex]::Replace($content, $versionPattern, $versionLine)
    }

    $generatedParagraph = "This repository was generated from an enhanced Aspire starter template. It includes the pieces most teams add immediately: identity, roles, admin pages, PostgreSQL, Redis, migrations, local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app."
    $content.Replace($generatedParagraph, "$generatedParagraph`r`n`r`n$versionLine")
}

dotnet pack (Join-Path $repoRoot "EnhancedAspireStarter.Templates.csproj") -c $Configuration
& (Join-Path $repoRoot "visualstudio\Build-Vsix.ps1") -Version $TemplateVersion

Write-Host "Updated template artifacts for version $TemplateVersion."
