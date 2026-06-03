param(
    [string] $TemplateSource = (Join-Path $PSScriptRoot "..\templates\enhanced-aspire-starter"),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot "..\artifacts\vsix"),
    [string] $Version = "0.1.1",
    [string] $Publisher = "vwzhang"
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-RelativePath([string] $BasePath, [string] $Path) {
    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/") + "\"
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.StartsWith($baseFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($baseFullPath.Length)
    }

    return $Path
}

function Test-TextTemplateFile([string] $Path) {
    $fileName = [System.IO.Path]::GetFileName($Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($fileName -in @(".gitignore", ".editorconfig", ".gitattributes")) {
        return $true
    }

    return $extension -in @(
        ".cs", ".csproj", ".json", ".razor", ".css", ".html", ".http", ".md",
        ".txt", ".slnx", ".config", ".props", ".targets", ".xml", ".yml", ".yaml"
    )
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Escape-Xml([string] $Value) {
    [System.Security.SecurityElement]::Escape($Value)
}

function Get-VisualStudioSdk {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe was not found. Install Visual Studio with the extension development workload."
    }

    $instanceJson = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VSSDK -format json
    if (-not $instanceJson) {
        throw "Visual Studio SDK was not found. Install the Visual Studio extension development workload."
    }

    $instance = $instanceJson | ConvertFrom-Json | Select-Object -First 1
    $installPath = $instance.installationPath
    $majorVersion = ([Version] $instance.installationVersion).Major
    $vssdkTargets = Join-Path $installPath "MSBuild\Microsoft\VisualStudio\v$majorVersion.0\VSSDK\Microsoft.VsSDK.targets"
    $vstoolsPath = Join-Path $installPath "VSSDK\VisualStudioIntegration\Tools"
    $msbuildPath = Join-Path $installPath "MSBuild\Current\Bin\MSBuild.exe"

    foreach ($path in @($vssdkTargets, $vstoolsPath, $msbuildPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required Visual Studio SDK path was not found: $path"
        }
    }

    [pscustomobject] @{
        InstallPath = $installPath
        MSBuildPath = $msbuildPath
        VSSDKTargets = $vssdkTargets
        VSToolsPath = $vstoolsPath
    }
}

function New-ZipFromDirectoryContent([string] $SourceDirectory, [string] $DestinationPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)

    try {
        $files = Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File -Force | Sort-Object FullName

        foreach ($file in $files) {
            $entryName = (Get-RelativePath $SourceDirectory $file.FullName).Replace("\", "/")
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip,
                $file.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Convert-ToTemplateTokenizedFiles([string] $Root) {
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force

    foreach ($file in $files) {
        if (-not (Test-TextTemplateFile $file.FullName)) {
            continue
        }

        $content = [System.IO.File]::ReadAllText($file.FullName)
        $content = $content.Replace("f6e76cbf-2d79-4b8b-9023-113ac10e07f9", '$guid1$')
        $content = $content.Replace("vwzhang", '$registeredorganization$')
        $content = $content.Replace("Starter", '$ext_safeprojectname$')
        [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.UTF8Encoding]::new($false))
    }
}

function Add-ProjectItemXml(
    [System.Xml.XmlWriter] $Writer,
    [string] $SourcePath,
    [string] $TargetFileName,
    [bool] $ReplaceParameters
) {
    $Writer.WriteStartElement("ProjectItem")
    $Writer.WriteAttributeString("ReplaceParameters", $ReplaceParameters.ToString().ToLowerInvariant())
    $Writer.WriteAttributeString("TargetFileName", $TargetFileName)
    $Writer.WriteString($SourcePath)
    $Writer.WriteEndElement()
}

function New-ProjectTemplateFile(
    [string] $ProjectDirectory,
    [string] $ProjectName,
    [string] $Description
) {
    $templatePath = Join-Path $ProjectDirectory "$ProjectName.vstemplate"
    $projectFile = "$ProjectName.csproj"
    $targetProjectFile = $projectFile.Replace("Starter", '$ext_safeprojectname$')

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true

    $writer = [System.Xml.XmlWriter]::Create($templatePath, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement("VSTemplate", "http://schemas.microsoft.com/developer/vstemplate/2005")
        $writer.WriteAttributeString("Version", "3.0.0")
        $writer.WriteAttributeString("Type", "Project")

        $writer.WriteStartElement("TemplateData")
        $shortProjectName = $ProjectName.Replace("Starter.", "")
        $writer.WriteElementString("Name", "Enhanced Aspire Starter $shortProjectName")
        $writer.WriteElementString("Description", $Description)
        $writer.WriteElementString("ProjectType", "CSharp")
        $writer.WriteElementString("Hidden", "true")
        $writer.WriteElementString("CreateNewFolder", "true")
        $writer.WriteEndElement()

        $writer.WriteStartElement("TemplateContent")
        $writer.WriteStartElement("Project")
        $writer.WriteAttributeString("File", $projectFile)
        $writer.WriteAttributeString("TargetFileName", $targetProjectFile)
        $writer.WriteAttributeString("ReplaceParameters", "true")

        $files = Get-ChildItem -LiteralPath $ProjectDirectory -Recurse -File -Force |
            Where-Object {
                $relativeCandidate = Get-RelativePath $ProjectDirectory $_.FullName
                $_.Name -ne "$ProjectName.vstemplate" -and
                $_.Name -ne $projectFile -and
                $relativeCandidate -notmatch "(^|\\)(bin|obj)(\\|$)"
            } |
            Sort-Object FullName

        foreach ($file in $files) {
            $relativePath = Get-RelativePath $ProjectDirectory $file.FullName
            $targetFileName = $relativePath

            if ($relativePath.StartsWith("_solution\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $targetFileName = "..\" + $relativePath.Substring("_solution\".Length)
            }

            $targetFileName = $targetFileName.Replace("Starter", '$ext_safeprojectname$')
            Add-ProjectItemXml $writer $relativePath $targetFileName (Test-TextTemplateFile $file.FullName)
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        $writer.Dispose()
    }
}

function Write-RootTemplate([string] $Path) {
    $content = @'
<?xml version="1.0" encoding="utf-8"?>
<VSTemplate Version="3.0.0" Type="ProjectGroup" xmlns="http://schemas.microsoft.com/developer/vstemplate/2005">
  <TemplateData>
    <Name>Enhanced Aspire Starter</Name>
    <Description>Opinionated .NET Aspire starter with Blazor, Identity, PostgreSQL, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
    <ProjectType>CSharp</ProjectType>
    <DefaultName>MyAspireStarter</DefaultName>
    <CreateNewFolder>true</CreateNewFolder>
    <ProvideDefaultName>true</ProvideDefaultName>
    <SortOrder>1000</SortOrder>
    <NumberOfParentCategoriesToRollUp>1</NumberOfParentCategoriesToRollUp>
  </TemplateData>
  <TemplateContent>
    <ProjectCollection>
      <ProjectTemplateLink ProjectName="$safeprojectname$.ApiService" CopyParameters="true">Starter.ApiService\Starter.ApiService.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.AppHost" CopyParameters="true">Starter.AppHost\Starter.AppHost.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.MigrationService" CopyParameters="true">Starter.MigrationService\Starter.MigrationService.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.ServiceDefaults" CopyParameters="true">Starter.ServiceDefaults\Starter.ServiceDefaults.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.Shared" CopyParameters="true">Starter.Shared\Starter.Shared.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.Tests" CopyParameters="true">Starter.Tests\Starter.Tests.vstemplate</ProjectTemplateLink>
      <ProjectTemplateLink ProjectName="$safeprojectname$.Web" CopyParameters="true">Starter.Web\Starter.Web.vstemplate</ProjectTemplateLink>
    </ProjectCollection>
  </TemplateContent>
</VSTemplate>
'@
    Write-Utf8NoBom $Path $content
}

function Write-VsixManifest([string] $Path, [string] $Version, [string] $Publisher) {
    $manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Id="Vwzhang.EnhancedAspireStarter.VisualStudio" Version="$Version" Language="en-US" Publisher="$Publisher" />
    <DisplayName>Enhanced Aspire Starter</DisplayName>
    <Description xml:space="preserve">Visual Studio project template for an enhanced .NET Aspire starter with Blazor, Identity, PostgreSQL, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
    <MoreInfo>https://github.com/vwzhang/Starter.Template</MoreInfo>
    <License>Resources\LICENSE.txt</License>
    <ReleaseNotes>Resources\ReleaseNotes.txt</ReleaseNotes>
    <Tags>Aspire; .NET; Blazor; ASP.NET Core; Identity; PostgreSQL; Redis; pgAdmin; smtp4dev; Project Template</Tags>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Community" Version="[17.0,19.0)">
      <ProductArchitecture>amd64</ProductArchitecture>
    </InstallationTarget>
    <InstallationTarget Id="Microsoft.VisualStudio.Pro" Version="[17.0,19.0)">
      <ProductArchitecture>amd64</ProductArchitecture>
    </InstallationTarget>
    <InstallationTarget Id="Microsoft.VisualStudio.Enterprise" Version="[17.0,19.0)">
      <ProductArchitecture>amd64</ProductArchitecture>
    </InstallationTarget>
  </Installation>
  <Dependencies>
    <Dependency Id="Microsoft.Framework.NDP" DisplayName="Microsoft .NET Framework" Version="[4.5,)" />
  </Dependencies>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.ProjectTemplate" Path="ProjectTemplates" />
  </Assets>
  <Prerequisites>
    <Prerequisite Id="Microsoft.VisualStudio.Component.CoreEditor" Version="[17.0,19.0)" DisplayName="Visual Studio core editor" />
  </Prerequisites>
</PackageManifest>
"@

    Write-Utf8NoBom $Path $manifest
}

function Write-VsixProjectFile(
    [string] $Path,
    [string] $VSSDKTargets
) {
    $escapedTargets = Escape-Xml $VSSDKTargets
    $content = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <OutputPath>bin\`$(Configuration)\</OutputPath>
    <IntermediateOutputPath>obj\`$(Configuration)\</IntermediateOutputPath>
    <TargetVsixContainer>`$(OutputPath)EnhancedAspireStarter.VisualStudio.vsix</TargetVsixContainer>
    <GeneratePkgDefFile>false</GeneratePkgDefFile>
    <IncludeAssemblyInVSIXContainer>false</IncludeAssemblyInVSIXContainer>
    <IncludeDebugSymbolsInVSIXContainer>false</IncludeDebugSymbolsInVSIXContainer>
    <CopyBuildOutputToOutputDirectory>false</CopyBuildOutputToOutputDirectory>
    <CreateVsixContainer>true</CreateVsixContainer>
    <DeployExtension>false</DeployExtension>
  </PropertyGroup>
  <ItemGroup>
    <None Include="source.extension.vsixmanifest" />
    <Content Include="ProjectTemplates\CSharp\Aspire\EnhancedAspireStarter.zip" IncludeInVSIX="true" VSIXSubPath="ProjectTemplates\CSharp\Aspire" />
    <Content Include="Resources\LICENSE.txt" IncludeInVSIX="true" VSIXSubPath="Resources" />
    <Content Include="Resources\ReleaseNotes.txt" IncludeInVSIX="true" VSIXSubPath="Resources" />
  </ItemGroup>
  <Import Project="$escapedTargets" />
</Project>
"@

    Write-Utf8NoBom $Path $content
}

$templateSourcePath = Resolve-FullPath $TemplateSource
$outputPath = Resolve-FullPath $OutputDirectory
$workPath = Join-Path $outputPath "obj"
$templateRoot = Join-Path $workPath "EnhancedAspireStarter"
$vsixProjectRoot = Join-Path $workPath "vsix-project"
$templateZip = Join-Path $vsixProjectRoot "ProjectTemplates\CSharp\Aspire\EnhancedAspireStarter.zip"
$vsixBuildOutput = Join-Path $vsixProjectRoot "bin\Release\EnhancedAspireStarter.VisualStudio.vsix"
$vsixPath = Join-Path $outputPath "EnhancedAspireStarter.VisualStudio.$Version.vsix"

if (-not (Test-Path -LiteralPath $templateSourcePath)) {
    throw "TemplateSource does not exist: $templateSourcePath"
}

$visualStudioSdk = Get-VisualStudioSdk

Remove-Item -LiteralPath $workPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $templateZip) -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $vsixProjectRoot "Resources") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $vsixProjectRoot "bin\Release") -Force | Out-Null
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$projects = @(
    "Starter.ApiService",
    "Starter.AppHost",
    "Starter.MigrationService",
    "Starter.ServiceDefaults",
    "Starter.Shared",
    "Starter.Tests",
    "Starter.Web"
)

foreach ($project in $projects) {
    Copy-Item -LiteralPath (Join-Path $templateSourcePath $project) -Destination (Join-Path $templateRoot $project) -Recurse -Force
}

$solutionStaging = Join-Path $templateRoot "Starter.AppHost\_solution"
New-Item -ItemType Directory -Path $solutionStaging -Force | Out-Null

foreach ($solutionItem in @(".gitignore", "aspire.config.json", "LICENSE", "README.md", "Starter.slnx")) {
    $sourcePath = Join-Path $templateSourcePath $solutionItem
    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $solutionStaging $solutionItem) -Force
    }
}

foreach ($solutionDirectory in @(".github", "docs")) {
    $sourcePath = Join-Path $templateSourcePath $solutionDirectory
    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $solutionStaging $solutionDirectory) -Recurse -Force
    }
}

Convert-ToTemplateTokenizedFiles $templateRoot
Write-RootTemplate (Join-Path $templateRoot "EnhancedAspireStarter.vstemplate")

$projectDescriptions = @{
    "Starter.ApiService" = "Minimal API backend with shared DTOs and PostgreSQL integration."
    "Starter.AppHost" = "Aspire AppHost that orchestrates PostgreSQL, Redis, pgAdmin, smtp4dev, API, migrations, and Blazor."
    "Starter.MigrationService" = "Worker service that applies EF Core migrations and seed data."
    "Starter.ServiceDefaults" = "Shared Aspire service defaults for health checks, telemetry, service discovery, and resilience."
    "Starter.Shared" = "DTO project shared by API and Blazor frontend."
    "Starter.Tests" = "Aspire integration tests for the distributed application."
    "Starter.Web" = "Blazor Web App with MudBlazor, Identity, admin modules, settings, and dev pages."
}

foreach ($project in $projects) {
    New-ProjectTemplateFile (Join-Path $templateRoot $project) $project $projectDescriptions[$project]
}

New-ZipFromDirectoryContent $templateRoot $templateZip
Copy-Item -LiteralPath (Join-Path $templateSourcePath "LICENSE") -Destination (Join-Path $vsixProjectRoot "Resources\LICENSE.txt") -Force
Write-Utf8NoBom (Join-Path $vsixProjectRoot "Resources\ReleaseNotes.txt") "Initial Visual Studio Marketplace package for the Enhanced Aspire Starter project template."
Write-VsixManifest (Join-Path $vsixProjectRoot "source.extension.vsixmanifest") $Version $Publisher
Write-VsixProjectFile (Join-Path $vsixProjectRoot "EnhancedAspireStarter.VisualStudio.csproj") $visualStudioSdk.VSSDKTargets

$msbuildArguments = @(
    (Join-Path $vsixProjectRoot "EnhancedAspireStarter.VisualStudio.csproj"),
    "/restore",
    "/t:CreateVsixContainer",
    "/p:Configuration=Release",
    "/p:VSToolsPath=$($visualStudioSdk.VSToolsPath)",
    "/v:minimal"
)

& $visualStudioSdk.MSBuildPath @msbuildArguments
if ($LASTEXITCODE -ne 0) {
    throw "VSIX build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $vsixBuildOutput)) {
    throw "VSIX build completed but output was not found: $vsixBuildOutput"
}

Copy-Item -LiteralPath $vsixBuildOutput -Destination $vsixPath -Force

Write-Host "Project template zip: $templateZip"
Write-Host "VSIX package: $vsixPath"
