param(
    [string] $SourceRepository = (Join-Path $PSScriptRoot "..\..\Starter"),
    [string] $TemplateVersion = "0.1.17",
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

function Remove-MarkdownSection([string] $Content, [string] $Heading) {
    $escapedHeading = [regex]::Escape($Heading)
    [regex]::Replace($Content, "(?ms)^## $escapedHeading\r?\n.*?(?=^## |\z)", "")
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
    public const string Name = "Aspire Admin Starter";
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
    $content = $content -replace 'EnhancedAspireStarter\.VisualStudio\.[0-9]+\.[0-9]+\.[0-9]+\.vsix', "EnhancedAspireStarter.VisualStudio.$TemplateVersion.vsix"
    $content -replace '-TemplateVersion [0-9]+\.[0-9]+\.[0-9]+', "-TemplateVersion $TemplateVersion"
}

Update-TextFile (Join-Path $repoRoot "visualstudio\README.md") {
    param($content)
    $content = $content -replace 'EnhancedAspireStarter\.VisualStudio\.[0-9]+\.[0-9]+\.[0-9]+\.vsix', "EnhancedAspireStarter.VisualStudio.$TemplateVersion.vsix"
    $content -replace '-TemplateVersion [0-9]+\.[0-9]+\.[0-9]+', "-TemplateVersion $TemplateVersion"
}

Update-TextFile (Join-Path $templateRoot "README.md") {
    param($content)
    $content = $content.Replace("## Why Use This", "## Why This App")
    $content = $content.Replace(
        "Starting from a blank Aspire template is clean, but the first useful admin app usually needs the same foundation again and again. Aspire Admin Starter packages that foundation into a working application you can run, inspect, rename, and extend.",
        "This application was generated from an enhanced Aspire template. It includes the foundation most teams add early: identity, roles, admin pages, runtime settings, a database provider, Redis, migrations, optional local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app.")
    $content = $content.Replace(
        "The migration service seeds local users in Development when ``--seed-users`` is enabled:",
        "The migration service seeds local users in Development when test user seeding is enabled:")
    $content = $content.Replace(
        "`dotnet aspire starter`, `aspire template`, `blazor admin starter`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api starter`, `smtp4dev`, `ef core migrations`, `redis output cache`.",
        "`dotnet aspire`, `aspire template`, `blazor admin`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api`, `smtp4dev`, `ef core migrations`, `redis output cache`.")
    $content = Remove-MarkdownSection $content "Create From The Template"
    $content = Remove-MarkdownSection $content "Current Template Roadmap"
    $generatedQuickStart = @"
Run the full stack from the solution directory:

``````powershell
aspire start --apphost Starter.AppHost/Starter.AppHost.csproj
``````
"@
    $content = [regex]::Replace(
        $content,
        '(?ms)^Clone and run the full stack:\r?\n\r?\n```powershell\r?\ngit clone https://github\.com/vwzhang/Starter\.git\r?\ncd Starter\r?\naspire start --apphost Starter\.AppHost/Starter\.AppHost\.csproj\r?\n```',
        $generatedQuickStart)
    $versionLine = "Template version: ``$TemplateVersion``. The same value is available in ``Starter.Shared.TemplateInfo.Version``."
    $versionPattern = 'Template version: `[^`]+`\. The same value is available in `Starter\.Shared\.TemplateInfo\.Version`\.'

    if ($content -match $versionPattern) {
        return [regex]::Replace($content, $versionPattern, $versionLine)
    }

    $generatedParagraph = "This application was generated from an enhanced Aspire template. It includes the foundation most teams add early: identity, roles, admin pages, runtime settings, a database provider, Redis, migrations, optional local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app."
    $content.Replace($generatedParagraph, "$generatedParagraph`r`n`r`n$versionLine")
}

dotnet pack (Join-Path $repoRoot "EnhancedAspireStarter.Templates.csproj") -c $Configuration
& (Join-Path $repoRoot "visualstudio\Build-Vsix.ps1") -Version $TemplateVersion

Write-Host "Updated template artifacts for version $TemplateVersion."
