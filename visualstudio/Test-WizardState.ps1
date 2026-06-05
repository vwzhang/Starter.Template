param(
    [string] $WizardAssembly = (Join-Path $PSScriptRoot "..\artifacts\vsix\obj\vsix-project\Wizard\bin\Release\EnhancedAspireStarter.Wizard.dll"),
    [string] $VisualStudioRoot = "C:\Program Files\Microsoft Visual Studio\18\Professional",
    [string] $ScratchRoot = (Join-Path $env:TEMP "AspireAdminStarterWizardState")
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Load-Assembly([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required assembly not found: $Path"
    }

    [System.Reflection.Assembly]::LoadFrom((Resolve-FullPath $Path)) | Out-Null
}

function New-Replacements(
    [string] $ProjectName,
    [string] $Provider,
    [string] $DatabaseName,
    [string] $SolutionRoot
) {
    $values = [System.Collections.Generic.Dictionary[string,string]]::new()
    $values['$ext_safeprojectname$'] = $ProjectName
    $values['$safeprojectname$'] = $ProjectName
    $values['$destinationdirectory$'] = $SolutionRoot
    $values['$solutiondirectory$'] = $SolutionRoot
    $values['$ext_aspireadmin_databaseprovider$'] = $Provider
    $values['$ext_aspireadmin_databasename$'] = $DatabaseName
    $values['$ext_aspireadmin_usesqlserver$'] = if ($Provider -eq "SqlServer") { "True" } else { "False" }
    $values['$ext_aspireadmin_usepostgresql$'] = if ($Provider -eq "PostgreSql") { "True" } else { "False" }
    $values['$ext_aspireadmin_includepgadmin$'] = "True"
    $values['$ext_aspireadmin_includepgadminforpostgresql$'] = if ($Provider -eq "PostgreSql") { "True" } else { "False" }
    $values['$ext_aspireadmin_includesmtp4dev$'] = "True"
    $values['$ext_aspireadmin_seeddevelopmenttestusersvalue$'] = "true"
    $values['$ext_aspireadmin_seedcatalogsampledatavalue$'] = "true"
    return $values
}

function New-NestedProjectGroupContent([string] $ProjectName, [string] $SolutionRoot) {
    $contentRoot = Join-Path $SolutionRoot $ProjectName
    New-Item -ItemType Directory -Path $contentRoot -Force | Out-Null
    '<Solution></Solution>' | Set-Content -LiteralPath (Join-Path $SolutionRoot "$ProjectName.slnx") -Encoding UTF8

    foreach ($suffix in @("Shared", "ServiceDefaults", "ApiService", "Web", "MigrationService", "Tests")) {
        $projectDirectory = Join-Path $contentRoot "$ProjectName.$suffix"
        New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
        '<Project Sdk="Microsoft.NET.Sdk"></Project>' |
            Set-Content -LiteralPath (Join-Path $projectDirectory "$ProjectName.$suffix.csproj") -Encoding UTF8
    }
}

function Invoke-WizardGeneration(
    [type] $WizardType,
    [object] $RunKind,
    [string] $ProjectName,
    [string] $Provider,
    [string] $DatabaseName
) {
    $solutionRoot = Join-Path $ScratchRoot $ProjectName
    New-NestedProjectGroupContent $ProjectName $solutionRoot

    $wizard = [Activator]::CreateInstance($WizardType)
    $replacements = New-Replacements $ProjectName $Provider $DatabaseName $solutionRoot
    $wizard.RunStarted($null, $replacements, $RunKind, @())
    $wizard.RunFinished()

    $appHostPath = Join-Path $solutionRoot "$ProjectName.AppHost\AppHost.cs"
    $slnxPath = Join-Path $solutionRoot "$ProjectName.slnx"

    [pscustomobject]@{
        ProjectName = $ProjectName
        Provider = $Provider
        DatabaseName = $DatabaseName
        SolutionRoot = $solutionRoot
        AppHostExists = Test-Path -LiteralPath $appHostPath
        NestedRootExists = Test-Path -LiteralPath (Join-Path $solutionRoot $ProjectName)
        AppHostText = if (Test-Path -LiteralPath $appHostPath) { Get-Content -LiteralPath $appHostPath -Raw } else { "" }
        SlnxText = if (Test-Path -LiteralPath $slnxPath) { Get-Content -LiteralPath $slnxPath -Raw } else { "" }
    }
}

function Add-Check([System.Collections.Generic.List[object]] $Checks, [string] $Name, [bool] $Passed) {
    $Checks.Add([pscustomobject]@{ Check = $Name; Passed = $Passed }) | Out-Null
}

$publicAssemblies = Join-Path $VisualStudioRoot "Common7\IDE\PublicAssemblies"
Load-Assembly (Join-Path $publicAssemblies "envdte.dll")
Load-Assembly (Join-Path $publicAssemblies "Microsoft.VisualStudio.Interop.dll")
Load-Assembly (Join-Path $publicAssemblies "Microsoft.VisualStudio.TemplateWizardInterface.dll")

$loadedWizardAssembly = [System.Reflection.Assembly]::LoadFrom((Resolve-FullPath $WizardAssembly))
$wizardType = $loadedWizardAssembly.GetTypes() |
    Where-Object { $_.FullName -eq "EnhancedAspireStarter.VisualStudio.EnhancedAspireStarterWizard" } |
    Select-Object -First 1
if ($null -eq $wizardType) {
    throw "Wizard type was not found in $WizardAssembly."
}
$runKind = [Enum]::Parse([Microsoft.VisualStudio.TemplateWizard.WizardRunKind], "AsNewProject")

Remove-Item -LiteralPath $ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

try {
    $sql = Invoke-WizardGeneration $wizardType $runKind "HarnessSql" "SqlServer" "harnesssqldb"
    $pg = Invoke-WizardGeneration $wizardType $runKind "HarnessPg" "PostgreSql" "harnesspgdb"
    $defaultDb = Invoke-WizardGeneration $wizardType $runKind "HarnessDefault" "PostgreSql" ""

    $checks = [System.Collections.Generic.List[object]]::new()
    Add-Check $checks "SQL AppHost created" $sql.AppHostExists
    Add-Check $checks "SQL provider and database name" ($sql.AppHostText -match "AddSqlServer" -and $sql.AppHostText -match "harnesssqldb")
    Add-Check $checks "SQL nested root removed" (-not $sql.NestedRootExists)
    Add-Check $checks "SQL solution has root AppHost" ($sql.SlnxText -match "HarnessSql\.AppHost/HarnessSql\.AppHost\.csproj")

    Add-Check $checks "PostgreSQL AppHost created" $pg.AppHostExists
    Add-Check $checks "PostgreSQL provider and database name" ($pg.AppHostText -match "AddPostgres" -and $pg.AppHostText -match "WithPgAdmin" -and $pg.AppHostText -match "harnesspgdb" -and $pg.AppHostText -notmatch "AddSqlServer")
    Add-Check $checks "PostgreSQL nested root removed" (-not $pg.NestedRootExists)
    Add-Check $checks "PostgreSQL solution has root AppHost" ($pg.SlnxText -match "HarnessPg\.AppHost/HarnessPg\.AppHost\.csproj")

    Add-Check $checks "Default database name from project name" ($defaultDb.AppHostText -match "harnessdefaultdb" -and $defaultDb.AppHostText -notmatch "starterdb")

    $checks | Format-Table -AutoSize

    if ($checks | Where-Object { -not $_.Passed }) {
        throw "Visual Studio wizard state regression detected."
    }
}
finally {
    Remove-Item -LiteralPath $ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
}
