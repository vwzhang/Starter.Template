param(
    [string] $SourceRepository = "C:\Aspire\Starter",
    [string] $TemplateContent = "C:\Aspire\Starter.Template\templates\enhanced-aspire-starter",
    [string] $TemplateVersion = "0.1.8"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath (Join-Path $SourceRepository ".git"))) {
    throw "SourceRepository must be a git repository: $SourceRepository"
}

if (Test-Path -LiteralPath $TemplateContent) {
    Get-ChildItem -LiteralPath $TemplateContent -Force |
        Where-Object { $_.Name -ne ".template.config" } |
        Remove-Item -Recurse -Force
}
else {
    New-Item -ItemType Directory -Path $TemplateContent -Force | Out-Null
}

$archive = Join-Path $env:TEMP "enhanced-aspire-starter-template-source.zip"
Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue

git -C $SourceRepository archive --format zip --output $archive HEAD
Expand-Archive -LiteralPath $archive -DestinationPath $TemplateContent -Force

Remove-Item -LiteralPath (Join-Path $TemplateContent "AGENTS.md") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $TemplateContent ".mcp.json") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $TemplateContent ".agents") -Recurse -Force -ErrorAction SilentlyContinue

$workspaceImage = Join-Path $TemplateContent "docs\assets\starter-workspace.png"
if (Test-Path -LiteralPath $workspaceImage) {
    Rename-Item -LiteralPath $workspaceImage -NewName "workspace.png" -Force
}

$readmePath = Join-Path $TemplateContent "README.md"
if (Test-Path -LiteralPath $readmePath) {
    $readme = Get-Content -LiteralPath $readmePath -Raw
    $readme = $readme.Replace("# Enhanced Aspire Starter", "# Starter")
    $readme = $readme.Replace("[![CI](https://github.com/vwzhang/Starter/actions/workflows/ci.yml/badge.svg)](https://github.com/vwzhang/Starter/actions/workflows/ci.yml)`r`n", "")
    $readme = $readme.Replace("[![CI](https://github.com/vwzhang/Starter/actions/workflows/ci.yml/badge.svg)](https://github.com/vwzhang/Starter/actions/workflows/ci.yml)`n", "")
    $readme = $readme.Replace(
        "An opinionated .NET 10 Aspire starter for building internal tools, admin portals, and full-stack line-of-business apps without spending the first day wiring infrastructure.",
        "An opinionated .NET 10 Aspire app foundation for building internal tools, admin portals, and full-stack line-of-business apps without spending the first day wiring infrastructure.")
    $readme = $readme.Replace("![Starter Workspace](docs/assets/starter-workspace.png)", "![Starter Workspace](docs/assets/workspace.png)")
    $readme = $readme.Replace("## Why This Starter", "## Why This App")
    $readme = $readme.Replace(
        "This repository is meant to be cloned or used as a GitHub template when you want a real app foundation instead of a blank demo. It includes the pieces most teams add immediately: identity, roles, admin pages, PostgreSQL, Redis, migrations, local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app.",
        "This repository was generated from an enhanced Aspire application template. It includes the pieces most teams add immediately: identity, roles, admin pages, PostgreSQL, Redis, migrations, local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app.")
    $readme = $readme.Replace(
        "`dotnet aspire starter`, `aspire template`, `blazor admin starter`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api starter`, `smtp4dev`, `ef core migrations`, `redis output cache`.",
        "`dotnet aspire`, `aspire template`, `blazor admin`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api`, `smtp4dev`, `ef core migrations`, `redis output cache`.")
    $versionLine = "Template version: ``$TemplateVersion``. The same value is available in ``Starter.Shared.TemplateInfo.Version``."
    $versionPattern = 'Template version: `[^`]+`\. The same value is available in `Starter\.Shared\.TemplateInfo\.Version`\.'

    if ($readme -match $versionPattern) {
        $readme = [regex]::Replace($readme, $versionPattern, $versionLine)
    }
    else {
        $generatedParagraph = "This repository was generated from an enhanced Aspire application template. It includes the pieces most teams add immediately: identity, roles, admin pages, PostgreSQL, Redis, migrations, local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app."
        $readme = $readme.Replace($generatedParagraph, "$generatedParagraph`r`n`r`n$versionLine")
    }

    Set-Content -LiteralPath $readmePath -Value $readme -NoNewline
}

$sharedDirectory = Join-Path $TemplateContent "Starter.Shared"
if (Test-Path -LiteralPath $sharedDirectory) {
    $templateInfoPath = Join-Path $sharedDirectory "TemplateInfo.cs"
    $templateInfo = @"
namespace Starter.Shared;

public static class TemplateInfo
{
    public const string Name = "Enhanced Aspire Template";
    public const string Version = "$TemplateVersion";
}
"@

    [System.IO.File]::WriteAllText($templateInfoPath, $templateInfo + "`n", [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Template source synchronized from $SourceRepository to $TemplateContent"
