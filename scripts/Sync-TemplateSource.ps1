param(
    [string] $SourceRepository = "C:\Aspire\Starter",
    [string] $TemplateContent = "C:\Aspire\Starter.Template\templates\enhanced-aspire-starter",
    [string] $TemplateVersion = "0.1.26"
)

$ErrorActionPreference = "Stop"

function Remove-MarkdownSection([string] $Content, [string] $Heading) {
    $escapedHeading = [regex]::Escape($Heading)
    [regex]::Replace($Content, "(?ms)^## $escapedHeading\r?\n.*?(?=^## |\z)", "")
}

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
        "A polished .NET 10 Aspire starter for internal tools, admin portals, and full-stack business apps. It gives you the infrastructure most projects need on day one: authentication, role-based admin pages, runtime settings, PostgreSQL, Redis, local email capture, migrations, a Minimal API, a Blazor frontend, shared DTOs, and a real database-backed CRUD slice.",
        "A polished .NET 10 Aspire app foundation for internal tools, admin portals, and full-stack business apps. It includes the infrastructure most projects need on day one: authentication, role-based admin pages, runtime settings, a database provider, Redis, optional local email capture, migrations, a Minimal API, a Blazor frontend, shared DTOs, and a real database-backed CRUD slice.")
    $readme = $readme.Replace("![Starter Workspace](docs/assets/starter-workspace.png)", "![Starter Workspace](docs/assets/workspace.png)")
    $readme = $readme.Replace("## Why Use This", "## Why This App")
    $readme = $readme.Replace(
        "Starting from a blank Aspire template is clean, but the first useful admin app usually needs the same foundation again and again. Enhanced Aspire Starter packages that foundation into a working application you can run, inspect, rename, and extend.",
        "This application was generated from an enhanced Aspire template. It includes the foundation most teams add early: identity, roles, admin pages, runtime settings, a database provider, Redis, migrations, optional local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app.")
    $readme = $readme.Replace(
        "The migration service seeds local users in Development when ``--seed-users`` is enabled:",
        "The migration service seeds local users in Development when test user seeding is enabled:")
    $readme = $readme.Replace(
        "`dotnet aspire starter`, `aspire template`, `blazor admin starter`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api starter`, `smtp4dev`, `ef core migrations`, `redis output cache`.",
        "`dotnet aspire`, `aspire template`, `blazor admin`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api`, `smtp4dev`, `ef core migrations`, `redis output cache`.")
    $readme = Remove-MarkdownSection $readme "Create From The Template"
    $readme = Remove-MarkdownSection $readme "Current Template Roadmap"
    $generatedQuickStart = @"
Run the full stack from the solution directory:

``````powershell
aspire start --apphost Starter.AppHost/Starter.AppHost.csproj
``````
"@
    $readme = [regex]::Replace(
        $readme,
        '(?ms)^Clone and run the full stack:\r?\n\r?\n```powershell\r?\ngit clone https://github\.com/vwzhang/Starter\.git\r?\ncd Starter\r?\naspire start --apphost Starter\.AppHost/Starter\.AppHost\.csproj\r?\n```',
        $generatedQuickStart)
    $versionLine = "Template version: ``$TemplateVersion``. The same value is available in ``Starter.Shared.TemplateInfo.Version``."
    $versionPattern = 'Template version: `[^`]+`\. The same value is available in `Starter\.Shared\.TemplateInfo\.Version`\.'

    if ($readme -match $versionPattern) {
        $readme = [regex]::Replace($readme, $versionPattern, $versionLine)
    }
    else {
        $generatedParagraph = "This application was generated from an enhanced Aspire template. It includes the foundation most teams add early: identity, roles, admin pages, runtime settings, a database provider, Redis, migrations, optional local email capture, typed DTOs, a Minimal API, a Blazor frontend, and an integration test that starts the distributed app."
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
    public const string Name = "Aspire Admin St" + "arter";
    public const string Version = "$TemplateVersion";
}
"@

    [System.IO.File]::WriteAllText($templateInfoPath, $templateInfo + "`n", [System.Text.UTF8Encoding]::new($false))
}

& (Join-Path $PSScriptRoot "Apply-DatabaseProviderTemplateSupport.ps1") -TemplateContent $TemplateContent

Write-Host "Template source synchronized from $SourceRepository to $TemplateContent"
