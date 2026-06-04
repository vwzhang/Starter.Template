param(
    [string] $TemplateSource = (Join-Path $PSScriptRoot "..\templates\enhanced-aspire-starter"),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot "..\artifacts\vsix"),
    [string] $Version = "0.1.23",
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

function Convert-DotNetTemplateConditionDirectives([string] $Content) {
    $content = $Content -replace '(?m)^[ \t]*//#if \(includeSmtp4dev\)\s*$', '$if$ ($ext_aspireadmin_includesmtp4dev$ == True)'
    $content = $content -replace '(?m)^[ \t]*//#if \(includePgAdminForPostgreSql\)\s*$', '$if$ ($ext_aspireadmin_includepgadminforpostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*//#if \(usePostgreSql\)\s*$', '$if$ ($ext_aspireadmin_usepostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*//#if \(useSqlServer\)\s*$', '$if$ ($ext_aspireadmin_usesqlserver$ == True)'
    $content = $content -replace '(?m)^[ \t]*<!--#if \(includeSmtp4dev\)\s*-->\s*$', '$if$ ($ext_aspireadmin_includesmtp4dev$ == True)'
    $content = $content -replace '(?m)^[ \t]*<!--#if \(includePgAdminForPostgreSql\)\s*-->\s*$', '$if$ ($ext_aspireadmin_includepgadminforpostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*<!--#if \(usePostgreSql\)\s*-->\s*$', '$if$ ($ext_aspireadmin_usepostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*<!--#if \(useSqlServer\)\s*-->\s*$', '$if$ ($ext_aspireadmin_usesqlserver$ == True)'
    $content = $content -replace '(?m)^[ \t]*@\*#if \(includeSmtp4dev\)\*@\s*$', '$if$ ($ext_aspireadmin_includesmtp4dev$ == True)'
    $content = $content -replace '(?m)^[ \t]*@\*#if \(includePgAdminForPostgreSql\)\*@\s*$', '$if$ ($ext_aspireadmin_includepgadminforpostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*@\*#if \(usePostgreSql\)\*@\s*$', '$if$ ($ext_aspireadmin_usepostgresql$ == True)'
    $content = $content -replace '(?m)^[ \t]*@\*#if \(useSqlServer\)\*@\s*$', '$if$ ($ext_aspireadmin_usesqlserver$ == True)'
    $content = $content -replace '(?m)^[ \t]*//#endif\s*$', '$endif$'
    $content = $content -replace '(?m)^[ \t]*<!--#endif\s*-->\s*$', '$endif$'
    $content = $content -replace '(?m)^[ \t]*@\*#endif\*@\s*$', '$endif$'
    $content = $content -replace '(?m)^[ \t]*@\*#(if|elseif|else|endif).*?\*@\s*(\r?\n)?', ''
    $content -replace '(?m)^[ \t]*<!--#(if|elseif|else|endif).*?-->\s*(\r?\n)?', ''
}

function Set-VsixProviderPackagePlaceholder(
    [string] $Path,
    [string] $PostgreSqlPackageName,
    [string] $SqlServerPackageName,
    [string] $PlaceholderName
) {
    $content = [System.IO.File]::ReadAllText($Path)
    $pattern = '(?ms)\r?\n\$if\$ \(\$ext_aspireadmin_usepostgresql\$ == True\)\r?\n[ \t]*<PackageReference Include="' +
        [regex]::Escape($PostgreSqlPackageName) +
        '" Version="[^"]+" />\r?\n\$endif\$\r?\n\$if\$ \(\$ext_aspireadmin_usesqlserver\$ == True\)\r?\n[ \t]*<PackageReference Include="' +
        [regex]::Escape($SqlServerPackageName) +
        '" Version="[^"]+" />\r?\n\$endif\$'
    $replacement = "`r`n    `$ext_aspireadmin_$PlaceholderName`$"
    $updated = [regex]::Replace($content, $pattern, $replacement)

    if ($updated -eq $content) {
        throw "Could not replace provider package conditional block in $Path"
    }

    Write-Utf8NoBom $Path $updated
}

function Convert-VsixProjectFileConditionals([string] $TemplateRoot) {
    Set-VsixProviderPackagePlaceholder `
        (Join-Path $TemplateRoot "Starter.AppHost\Starter.AppHost.csproj") `
        "Aspire.Hosting.PostgreSQL" `
        "Aspire.Hosting.SqlServer" `
        "apphostdatabasepackagereference"

    foreach ($projectFile in @(
        (Join-Path $TemplateRoot "Starter.ApiService\Starter.ApiService.csproj"),
        (Join-Path $TemplateRoot "Starter.MigrationService\Starter.MigrationService.csproj")
    )) {
        Set-VsixProviderPackagePlaceholder `
            $projectFile `
            "Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" `
            "Aspire.Microsoft.EntityFrameworkCore.SqlServer" `
            "aspireefdatabasepackagereference"
    }

    Set-VsixProviderPackagePlaceholder `
        (Join-Path $TemplateRoot "Starter.Web\Starter.Web.csproj") `
        "Npgsql.EntityFrameworkCore.PostgreSQL" `
        "Microsoft.EntityFrameworkCore.SqlServer" `
        "webefdatabasepackagereference"
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

    $templateWizardInterfacePath = Join-Path $installPath "Common7\IDE\PublicAssemblies\Microsoft.VisualStudio.TemplateWizardInterface.dll"
    $envDtePath = Join-Path $installPath "Common7\IDE\PublicAssemblies\EnvDTE.dll"
    $visualStudioInteropPath = Join-Path $installPath "Common7\IDE\PublicAssemblies\Microsoft.VisualStudio.Interop.dll"

    foreach ($path in @($templateWizardInterfacePath, $envDtePath, $visualStudioInteropPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required Visual Studio wizard reference was not found: $path"
        }
    }

    [pscustomobject] @{
        InstallPath = $installPath
        MSBuildPath = $msbuildPath
        VSSDKTargets = $vssdkTargets
        VSToolsPath = $vstoolsPath
        TemplateWizardInterfacePath = $templateWizardInterfacePath
        EnvDtePath = $envDtePath
        VisualStudioInteropPath = $visualStudioInteropPath
    }
}

function Write-WizardProjectFiles(
    [string] $WizardDirectory,
    [string] $TemplateWizardInterfacePath,
    [string] $EnvDtePath,
    [string] $VisualStudioInteropPath
) {
    New-Item -ItemType Directory -Path $WizardDirectory -Force | Out-Null

    $escapedTemplateWizardInterfacePath = Escape-Xml $TemplateWizardInterfacePath
    $escapedEnvDtePath = Escape-Xml $EnvDtePath
    $escapedVisualStudioInteropPath = Escape-Xml $VisualStudioInteropPath
    $projectFile = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <AssemblyName>EnhancedAspireStarter.Wizard</AssemblyName>
    <RootNamespace>EnhancedAspireStarter.VisualStudio</RootNamespace>
    <OutputPath>bin\`$(Configuration)\</OutputPath>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <Nullable>disable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="System" />
    <Reference Include="System.Core" />
    <Reference Include="System.Drawing" />
    <Reference Include="System.Windows.Forms" />
    <Reference Include="EnvDTE">
      <HintPath>$escapedEnvDtePath</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="Microsoft.VisualStudio.Interop">
      <HintPath>$escapedVisualStudioInteropPath</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="Microsoft.VisualStudio.TemplateWizardInterface">
      <HintPath>$escapedTemplateWizardInterfacePath</HintPath>
      <Private>false</Private>
    </Reference>
  </ItemGroup>
</Project>
"@

    Write-Utf8NoBom (Join-Path $WizardDirectory "EnhancedAspireStarter.Wizard.csproj") $projectFile

    $wizardCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
using EnvDTE;
using Microsoft.VisualStudio.TemplateWizard;

namespace EnhancedAspireStarter.VisualStudio
{
    public sealed class EnhancedAspireStarterWizard : IWizard
    {
        private static WizardOptions configuredOptions;
        private readonly List<string> projectDirectories = new List<string>();
        private string destinationDirectory;
        private DTE dte;
        private string requestedProjectName;
        private string solutionDirectory;
        private WizardOptions options;

        public void RunStarted(
            object automationObject,
            Dictionary<string, string> replacementsDictionary,
            WizardRunKind runKind,
            object[] customParams)
        {
            dte = automationObject as DTE;
            var projectName = GetReplacement(
                replacementsDictionary,
                "$ext_safeprojectname$",
                GetReplacement(replacementsDictionary, "$safeprojectname$", "MyAspireAdmin"));
            requestedProjectName = projectName;
            destinationDirectory = GetReplacement(replacementsDictionary, "$destinationdirectory$", string.Empty);
            solutionDirectory = GetReplacement(replacementsDictionary, "$solutiondirectory$", string.Empty);
            var defaultDatabaseName = ToResourceName(projectName) + "db";
            Application.EnableVisualStyles();
            var owner = OwnerWindow.FromAutomationObject(automationObject);

            options = configuredOptions ?? TryReadCopiedOptions(replacementsDictionary);

            if (options == null)
            {
                using (var form = new OptionsForm(defaultDatabaseName))
                {
                    var result = owner == null ? form.ShowDialog() : form.ShowDialog(owner);
                    if (result != DialogResult.OK)
                    {
                        throw new WizardCancelledException("Enhanced Aspire Starter creation was canceled.");
                    }

                    options = WizardOptions.FromForm(form);
                }
            }

            configuredOptions = options;
            SetOptionReplacements(replacementsDictionary, options);
        }

        public void ProjectFinishedGenerating(Project project)
        {
            if (project == null || string.IsNullOrWhiteSpace(project.FullName))
            {
                return;
            }

            var projectDirectory = Path.GetDirectoryName(project.FullName);
            if (!string.IsNullOrWhiteSpace(projectDirectory) && !projectDirectories.Contains(projectDirectory, StringComparer.OrdinalIgnoreCase))
            {
                projectDirectories.Add(projectDirectory);
            }

            CleanGeneratedRoot(projectDirectory);
            SetAppHostStartupProject();
        }

        public void ProjectItemFinishedGenerating(ProjectItem projectItem)
        {
        }

        public bool ShouldAddProjectItem(string filePath)
        {
            var normalizedPath = (filePath ?? string.Empty).Replace('/', '\\');

            if (normalizedPath.IndexOf("\\Migrations.SqlServer\\", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return options != null && options.UseSqlServer;
            }

            if (options != null && options.UseSqlServer && normalizedPath.IndexOf("\\Migrations\\", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return false;
            }

            return true;
        }

        public void BeforeOpeningFile(ProjectItem projectItem)
        {
        }

        public void RunFinished()
        {
            CaptureSolutionProjectDirectories();
            SetAppHostStartupProject();

            var root = GetGeneratedRoot();
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                return;
            }

            CleanGeneratedRoot(root);
            SetAppHostStartupProject();
        }

        private void CleanGeneratedRoot(string root)
        {
            if (options == null || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                return;
            }

            DeleteInactiveMigrationDirectories(root);
            ProcessConditionalTemplateBlocks(root);
        }

        private void CaptureSolutionProjectDirectories()
        {
            if (dte == null || dte.Solution == null)
            {
                return;
            }

            foreach (var project in GetSolutionProjects())
            {
                if (project == null || string.IsNullOrWhiteSpace(project.FullName))
                {
                    continue;
                }

                var projectDirectory = Path.GetDirectoryName(project.FullName);
                if (!string.IsNullOrWhiteSpace(projectDirectory) && !projectDirectories.Contains(projectDirectory, StringComparer.OrdinalIgnoreCase))
                {
                    projectDirectories.Add(projectDirectory);
                }
            }
        }

        private IEnumerable<Project> GetSolutionProjects()
        {
            if (dte == null || dte.Solution == null)
            {
                yield break;
            }

            foreach (Project project in dte.Solution.Projects)
            {
                foreach (var childProject in EnumerateProjects(project))
                {
                    yield return childProject;
                }
            }
        }

        private static IEnumerable<Project> EnumerateProjects(Project project)
        {
            if (project == null)
            {
                yield break;
            }

            yield return project;

            if (project.ProjectItems == null)
            {
                yield break;
            }

            foreach (ProjectItem item in project.ProjectItems)
            {
                Project subProject = null;

                try
                {
                    subProject = item.SubProject;
                }
                catch
                {
                    subProject = null;
                }

                if (subProject == null)
                {
                    continue;
                }

                foreach (var childProject in EnumerateProjects(subProject))
                {
                    yield return childProject;
                }
            }
        }

        private void SetAppHostStartupProject()
        {
            if (dte == null || dte.Solution == null)
            {
                return;
            }

            var appHostProject = GetSolutionProjects()
                .FirstOrDefault(project =>
                    !string.IsNullOrWhiteSpace(project.FullName)
                    && project.FullName.EndsWith(".AppHost.csproj", StringComparison.OrdinalIgnoreCase));

            if (appHostProject == null || string.IsNullOrWhiteSpace(appHostProject.UniqueName))
            {
                return;
            }

            dte.Solution.SolutionBuild.StartupProjects = appHostProject.UniqueName;
        }

        private string GetGeneratedRoot()
        {
            var firstProjectDirectory = projectDirectories.FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(firstProjectDirectory))
            {
                var parent = Directory.GetParent(firstProjectDirectory);
                if (parent == null)
                {
                    return firstProjectDirectory;
                }

                var parentPath = parent.FullName.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                return projectDirectories.All(path => path.StartsWith(parentPath, StringComparison.OrdinalIgnoreCase))
                    ? parent.FullName
                    : firstProjectDirectory;
            }

            foreach (var candidate in GetRootCandidates())
            {
                var root = NormalizeGeneratedRootCandidate(candidate);
                if (!string.IsNullOrWhiteSpace(root))
                {
                    return root;
                }
            }

            return string.Empty;
        }

        private IEnumerable<string> GetRootCandidates()
        {
            if (!string.IsNullOrWhiteSpace(solutionDirectory))
            {
                yield return solutionDirectory;
            }

            if (!string.IsNullOrWhiteSpace(destinationDirectory))
            {
                yield return destinationDirectory;
            }

            if (!string.IsNullOrWhiteSpace(destinationDirectory))
            {
                var parent = Directory.GetParent(destinationDirectory);
                if (parent != null)
                {
                    yield return parent.FullName;
                }
            }

            if (dte != null && dte.Solution != null && !string.IsNullOrWhiteSpace(dte.Solution.FullName))
            {
                var solutionFileDirectory = Path.GetDirectoryName(dte.Solution.FullName);
                if (!string.IsNullOrWhiteSpace(solutionFileDirectory))
                {
                    yield return solutionFileDirectory;
                }
            }
        }

        private string NormalizeGeneratedRootCandidate(string candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate) || !Directory.Exists(candidate))
            {
                return string.Empty;
            }

            var directoryName = Path.GetFileName(candidate.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            if (!string.IsNullOrWhiteSpace(directoryName)
                && directoryName.EndsWith(".AppHost", StringComparison.OrdinalIgnoreCase)
                && Directory.GetParent(candidate) != null)
            {
                var parent = Directory.GetParent(candidate).FullName;
                if (HasAppHostProject(parent))
                {
                    return parent;
                }
            }

            if (HasAppHostProject(candidate))
            {
                return candidate;
            }

            if (!string.IsNullOrWhiteSpace(requestedProjectName))
            {
                var nestedProjectRoot = Path.Combine(candidate, requestedProjectName + ".AppHost");
                if (Directory.Exists(nestedProjectRoot) && HasAppHostProject(candidate))
                {
                    return candidate;
                }
            }

            return string.Empty;
        }

        private static bool HasAppHostProject(string root)
        {
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                return false;
            }

            return Directory.GetFiles(root, "*.AppHost.csproj", SearchOption.AllDirectories).Any();
        }

        private void DeleteInactiveMigrationDirectories(string root)
        {
            var inactiveDirectoryName = options.UseSqlServer ? "Migrations" : "Migrations.SqlServer";

            foreach (var directory in Directory.GetDirectories(root, inactiveDirectoryName, SearchOption.AllDirectories))
            {
                if (!IsProviderMigrationDirectory(directory))
                {
                    continue;
                }

                Directory.Delete(directory, true);
            }
        }

        private static bool IsProviderMigrationDirectory(string directory)
        {
            var normalized = directory.Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar);
            var parent = Directory.GetParent(directory);

            return parent != null
                && parent.Name.Equals("Data", StringComparison.OrdinalIgnoreCase)
                && (normalized.IndexOf(".Web" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) >= 0
                    || normalized.IndexOf(".ApiService" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) >= 0);
        }

        private void ProcessConditionalTemplateBlocks(string root)
        {
            foreach (var file in Directory.GetFiles(root, "*.*", SearchOption.AllDirectories))
            {
                if (!IsTextTemplateOutput(file))
                {
                    continue;
                }

                var content = File.ReadAllText(file);
                if (content.IndexOf("$if$", StringComparison.Ordinal) < 0)
                {
                    continue;
                }

                var processed = ProcessConditionalTemplateContent(content);
                if (!string.Equals(content, processed, StringComparison.Ordinal))
                {
                    File.WriteAllText(file, processed, new UTF8Encoding(false));
                }
            }
        }

        private static bool IsTextTemplateOutput(string file)
        {
            var extension = Path.GetExtension(file).ToLowerInvariant();
            return extension == ".cs"
                || extension == ".csproj"
                || extension == ".json"
                || extension == ".razor"
                || extension == ".css"
                || extension == ".html"
                || extension == ".http"
                || extension == ".md"
                || extension == ".txt"
                || extension == ".slnx"
                || extension == ".config"
                || extension == ".props"
                || extension == ".targets"
                || extension == ".xml"
                || extension == ".yml"
                || extension == ".yaml";
        }

        private string ProcessConditionalTemplateContent(string content)
        {
            var lines = content.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
            var output = new List<string>();
            var stack = new Stack<bool>();
            var includeLine = true;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                bool conditionEnabled;

                if (TryGetConditionValue(trimmed, out conditionEnabled))
                {
                    stack.Push(includeLine);
                    includeLine = includeLine && conditionEnabled;
                    continue;
                }

                if (trimmed.Equals("$endif$", StringComparison.Ordinal))
                {
                    includeLine = stack.Count > 0 ? stack.Pop() : true;
                    continue;
                }

                if (includeLine)
                {
                    output.Add(line);
                }
            }

            return string.Join(Environment.NewLine, output);
        }

        private bool TryGetConditionValue(string line, out bool enabled)
        {
            enabled = false;

            if (!line.StartsWith("$if$", StringComparison.Ordinal))
            {
                return false;
            }

            if (line.IndexOf("True == True", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                enabled = true;
                return true;
            }

            if (line.IndexOf("False == True", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                enabled = false;
                return true;
            }

            var start = line.IndexOf("$ext_aspireadmin_", StringComparison.Ordinal);
            if (start < 0)
            {
                return false;
            }

            var end = line.IndexOf('$', start + 1);
            if (end <= start)
            {
                return false;
            }

            var conditionKey = line.Substring(start + 1, end - start - 1);
            enabled = IsConditionEnabled(conditionKey);
            return true;
        }

        private bool IsConditionEnabled(string conditionKey)
        {
            if (conditionKey.Equals("ext_aspireadmin_includesmtp4dev", StringComparison.OrdinalIgnoreCase))
            {
                return options != null && options.IncludeSmtp4dev;
            }

            if (conditionKey.Equals("ext_aspireadmin_includepgadminforpostgresql", StringComparison.OrdinalIgnoreCase))
            {
                return options != null && options.IncludePgAdminForPostgreSql;
            }

            if (conditionKey.Equals("ext_aspireadmin_usepostgresql", StringComparison.OrdinalIgnoreCase))
            {
                return options != null && options.UsePostgreSql;
            }

            if (conditionKey.Equals("ext_aspireadmin_usesqlserver", StringComparison.OrdinalIgnoreCase))
            {
                return options != null && options.UseSqlServer;
            }

            return false;
        }

        private static string GetReplacement(
            IDictionary<string, string> replacements,
            string key,
            string fallback)
        {
            string value;
            return replacements.TryGetValue(key, out value) && !string.IsNullOrWhiteSpace(value)
                ? value
                : fallback;
        }

        private static void SetReplacement(
            IDictionary<string, string> replacements,
            string key,
            string value)
        {
            if (replacements.ContainsKey(key))
            {
                replacements[key] = value;
                return;
            }

            replacements.Add(key, value);
        }

        private static string ToTemplateBoolean(bool value)
        {
            return value ? "True" : "False";
        }

        private static string ToResourceName(string value)
        {
            var characters = value
                .Where(char.IsLetterOrDigit)
                .Select(char.ToLowerInvariant)
                .ToArray();

            return characters.Length == 0 ? "app" : new string(characters);
        }

        private static WizardOptions TryReadCopiedOptions(IDictionary<string, string> replacements)
        {
            var provider = GetReplacement(
                replacements,
                "$ext_aspireadmin_databaseprovider$",
                GetReplacement(replacements, "$aspireadmin_databaseprovider$", string.Empty));

            if (string.IsNullOrWhiteSpace(provider))
            {
                return null;
            }

            var useSqlServer = provider.Equals("SqlServer", StringComparison.OrdinalIgnoreCase)
                || ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_usesqlserver$", "False"));
            var databaseName = GetReplacement(
                replacements,
                "$ext_aspireadmin_databasename$",
                GetReplacement(replacements, "$aspireadmin_databasename$", "starterdb"));

            return WizardOptions.FromValues(
                useSqlServer,
                databaseName,
                ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_includepgadmin$", "True")),
                ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_includepgadminforpostgresql$", useSqlServer ? "False" : "True")),
                ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_includesmtp4dev$", "True")),
                ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_seeddevelopmenttestusersvalue$", "true")),
                ParseTemplateBoolean(GetReplacement(replacements, "$ext_aspireadmin_seedcatalogsampledatavalue$", "true")));
        }

        private static void SetOptionReplacements(IDictionary<string, string> replacements, WizardOptions options)
        {
            SetAspireReplacement(replacements, "databaseprovider", options.DatabaseProvider);
            SetAspireReplacement(replacements, "usepostgresql", ToTemplateBoolean(options.UsePostgreSql));
            SetAspireReplacement(replacements, "usesqlserver", ToTemplateBoolean(options.UseSqlServer));
            SetAspireReplacement(replacements, "databasename", options.DatabaseName);
            SetAspireReplacement(replacements, "includepgadmin", ToTemplateBoolean(options.IncludePgAdmin));
            SetAspireReplacement(replacements, "includepgadminforpostgresql", ToTemplateBoolean(options.IncludePgAdminForPostgreSql));
            SetAspireReplacement(replacements, "includesmtp4dev", ToTemplateBoolean(options.IncludeSmtp4dev));
            SetAspireReplacement(replacements, "apphostdatabasepackagereference", options.AppHostDatabasePackageReference);
            SetAspireReplacement(replacements, "aspireefdatabasepackagereference", options.AspireEfDatabasePackageReference);
            SetAspireReplacement(replacements, "webefdatabasepackagereference", options.WebEfDatabasePackageReference);
            SetAspireReplacement(replacements, "seedcatalogsampledatavalue", options.SeedSampleData ? "true" : "false");
            SetAspireReplacement(replacements, "seeddevelopmenttestusersvalue", options.SeedUsers ? "true" : "false");
        }

        private static void SetAspireReplacement(IDictionary<string, string> replacements, string name, string value)
        {
            SetReplacement(replacements, "$aspireadmin_" + name + "$", value);
            SetReplacement(replacements, "$ext_aspireadmin_" + name + "$", value);
        }

        private static bool ParseTemplateBoolean(string value)
        {
            return value != null
                && (value.Equals("true", StringComparison.OrdinalIgnoreCase)
                    || value.Equals("True", StringComparison.Ordinal)
                    || value.Equals("1", StringComparison.OrdinalIgnoreCase));
        }
    }

    internal sealed class WizardOptions
    {
        private WizardOptions(
            bool useSqlServer,
            string databaseName,
            bool includePgAdmin,
            bool includePgAdminForPostgreSql,
            bool includeSmtp4dev,
            bool seedUsers,
            bool seedSampleData)
        {
            UseSqlServer = useSqlServer;
            UsePostgreSql = !useSqlServer;
            DatabaseProvider = useSqlServer ? "SqlServer" : "PostgreSql";
            DatabaseName = string.IsNullOrWhiteSpace(databaseName) ? "starterdb" : databaseName;
            IncludePgAdmin = includePgAdmin;
            IncludePgAdminForPostgreSql = !useSqlServer && includePgAdminForPostgreSql;
            IncludeSmtp4dev = includeSmtp4dev;
            SeedUsers = seedUsers;
            SeedSampleData = seedSampleData;
        }

        public bool UsePostgreSql { get; private set; }
        public bool UseSqlServer { get; private set; }
        public string DatabaseProvider { get; private set; }
        public string DatabaseName { get; private set; }
        public bool IncludePgAdmin { get; private set; }
        public bool IncludePgAdminForPostgreSql { get; private set; }
        public bool IncludeSmtp4dev { get; private set; }
        public bool SeedUsers { get; private set; }
        public bool SeedSampleData { get; private set; }

        public string AppHostDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Aspire.Hosting.SqlServer\" Version=\"13.4.0\" />"
                    : "<PackageReference Include=\"Aspire.Hosting.PostgreSQL\" Version=\"13.4.0\" />";
            }
        }

        public string AspireEfDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Aspire.Microsoft.EntityFrameworkCore.SqlServer\" Version=\"13.4.0\" />"
                    : "<PackageReference Include=\"Aspire.Npgsql.EntityFrameworkCore.PostgreSQL\" Version=\"13.4.0\" />";
            }
        }

        public string WebEfDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Microsoft.EntityFrameworkCore.SqlServer\" Version=\"10.0.8\" />"
                    : "<PackageReference Include=\"Npgsql.EntityFrameworkCore.PostgreSQL\" Version=\"10.0.2\" />";
            }
        }

        public static WizardOptions FromForm(OptionsForm form)
        {
            return new WizardOptions(
                form.UseSqlServer,
                form.DatabaseName,
                form.IncludePgAdmin,
                form.IncludePgAdminForPostgreSql,
                form.IncludeSmtp4dev,
                form.SeedUsers,
                form.SeedSampleData);
        }

        public static WizardOptions FromValues(
            bool useSqlServer,
            string databaseName,
            bool includePgAdmin,
            bool includePgAdminForPostgreSql,
            bool includeSmtp4dev,
            bool seedUsers,
            bool seedSampleData)
        {
            return new WizardOptions(
                useSqlServer,
                databaseName,
                includePgAdmin,
                includePgAdminForPostgreSql,
                includeSmtp4dev,
                seedUsers,
                seedSampleData);
        }
    }

    internal sealed class OwnerWindow : IWin32Window
    {
        private OwnerWindow(IntPtr handle)
        {
            Handle = handle;
        }

        public IntPtr Handle { get; private set; }

        public static OwnerWindow FromAutomationObject(object automationObject)
        {
            var dte = automationObject as DTE;
            if (dte == null || dte.MainWindow == null)
            {
                return null;
            }

            var handle = dte.MainWindow.HWnd;
            return handle == IntPtr.Zero ? null : new OwnerWindow(handle);
        }
    }

    internal sealed class OptionsForm : Form
    {
        private readonly ComboBox databaseProviderComboBox;
        private readonly TextBox databaseNameTextBox;
        private readonly CheckBox includePgAdminCheckBox;
        private readonly CheckBox includeSmtp4devCheckBox;
        private readonly CheckBox seedUsersCheckBox;
        private readonly CheckBox seedSampleDataCheckBox;

        public OptionsForm(string defaultDatabaseName)
        {
            Text = "Enhanced Aspire Starter options";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MinimizeBox = false;
            MaximizeBox = false;
            ShowInTaskbar = false;
            ClientSize = new Size(560, 430);
            Font = SystemFonts.MessageBoxFont;

            var titleLabel = new Label
            {
                Text = "Choose starter options",
                Font = new Font(Font.FontFamily, 12, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(20, 18)
            };

            var descriptionLabel = new Label
            {
                Text = "These options match the dotnet new template switches and are applied to the generated Aspire solution.",
                AutoSize = false,
                Location = new Point(20, 50),
                Size = new Size(520, 38)
            };

            var databaseProviderLabel = new Label
            {
                Text = "Database provider",
                AutoSize = true,
                Location = new Point(20, 100)
            };

            databaseProviderComboBox = new ComboBox
            {
                DropDownStyle = ComboBoxStyle.DropDownList,
                Location = new Point(20, 122),
                Size = new Size(520, 23)
            };
            databaseProviderComboBox.Items.Add("PostgreSQL");
            databaseProviderComboBox.Items.Add("SQL Server");
            databaseProviderComboBox.SelectedIndex = 0;
            databaseProviderComboBox.SelectedIndexChanged += delegate { UpdateProviderOptions(); };

            var databaseNameLabel = new Label
            {
                Text = "Database name",
                AutoSize = true,
                Location = new Point(20, 158)
            };

            databaseNameTextBox = new TextBox
            {
                Text = defaultDatabaseName,
                Location = new Point(20, 180),
                Size = new Size(520, 23),
                BorderStyle = BorderStyle.FixedSingle
            };

            includePgAdminCheckBox = new CheckBox
            {
                Text = "Include pgAdmin",
                Checked = true,
                AutoSize = true,
                Location = new Point(20, 222)
            };

            includeSmtp4devCheckBox = new CheckBox
            {
                Text = "Include smtp4dev local email capture",
                Checked = true,
                AutoSize = true,
                Location = new Point(20, 252)
            };

            seedUsersCheckBox = new CheckBox
            {
                Text = "Seed admin, manager, and user test accounts",
                Checked = true,
                AutoSize = true,
                Location = new Point(20, 282)
            };

            seedSampleDataCheckBox = new CheckBox
            {
                Text = "Seed catalog sample data",
                Checked = true,
                AutoSize = true,
                Location = new Point(20, 312)
            };

            var separator = new Panel
            {
                Location = new Point(20, 366),
                Size = new Size(520, 1)
            };

            var okButton = new Button
            {
                Text = "Next",
                DialogResult = DialogResult.OK,
                Location = new Point(360, 384),
                Size = new Size(82, 28)
            };
            okButton.Click += ValidateAndClose;

            var cancelButton = new Button
            {
                Text = "Cancel",
                DialogResult = DialogResult.Cancel,
                Location = new Point(458, 384),
                Size = new Size(82, 28)
            };

            Controls.AddRange(new Control[]
            {
                titleLabel,
                descriptionLabel,
                databaseProviderLabel,
                databaseProviderComboBox,
                databaseNameLabel,
                databaseNameTextBox,
                includePgAdminCheckBox,
                includeSmtp4devCheckBox,
                seedUsersCheckBox,
                seedSampleDataCheckBox,
                separator,
                okButton,
                cancelButton
            });

            AcceptButton = okButton;
            CancelButton = cancelButton;
            UpdateProviderOptions();
            ApplyVisualStudioTheme(separator, okButton, cancelButton);
        }

        public string DatabaseProvider
        {
            get { return UseSqlServer ? "SqlServer" : "PostgreSql"; }
        }

        public bool UsePostgreSql
        {
            get { return databaseProviderComboBox.SelectedIndex != 1; }
        }

        public bool UseSqlServer
        {
            get { return databaseProviderComboBox.SelectedIndex == 1; }
        }

        public string DatabaseName
        {
            get { return NormalizeDatabaseName(databaseNameTextBox.Text); }
        }

        public bool IncludePgAdmin
        {
            get { return includePgAdminCheckBox.Checked; }
        }

        public bool IncludePgAdminForPostgreSql
        {
            get { return UsePostgreSql && IncludePgAdmin; }
        }

        public bool IncludeSmtp4dev
        {
            get { return includeSmtp4devCheckBox.Checked; }
        }

        public string AppHostDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Aspire.Hosting.SqlServer\" Version=\"13.4.0\" />"
                    : "<PackageReference Include=\"Aspire.Hosting.PostgreSQL\" Version=\"13.4.0\" />";
            }
        }

        public string AspireEfDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Aspire.Microsoft.EntityFrameworkCore.SqlServer\" Version=\"13.4.0\" />"
                    : "<PackageReference Include=\"Aspire.Npgsql.EntityFrameworkCore.PostgreSQL\" Version=\"13.4.0\" />";
            }
        }

        public string WebEfDatabasePackageReference
        {
            get
            {
                return UseSqlServer
                    ? "<PackageReference Include=\"Microsoft.EntityFrameworkCore.SqlServer\" Version=\"10.0.8\" />"
                    : "<PackageReference Include=\"Npgsql.EntityFrameworkCore.PostgreSQL\" Version=\"10.0.2\" />";
            }
        }

        public bool SeedUsers
        {
            get { return seedUsersCheckBox.Checked; }
        }

        public bool SeedSampleData
        {
            get { return seedSampleDataCheckBox.Checked; }
        }

        private void ValidateAndClose(object sender, EventArgs e)
        {
            var databaseName = NormalizeDatabaseName(databaseNameTextBox.Text);

            if (string.IsNullOrWhiteSpace(databaseName))
            {
                MessageBox.Show(
                    this,
                    "Enter a database name. Use letters, numbers, underscore, or hyphen.",
                    "Enhanced Aspire Starter",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
                return;
            }

            databaseNameTextBox.Text = databaseName;
        }

        private static string NormalizeDatabaseName(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return string.Empty;
            }

            var characters = value
                .Trim()
                .Where(character => char.IsLetterOrDigit(character) || character == '_' || character == '-')
                .ToArray();

            return new string(characters);
        }

        private void ApplyVisualStudioTheme(Panel separator, Button okButton, Button cancelButton)
        {
            var theme = VsTheme.Current;

            BackColor = theme.DialogBackground;
            ForeColor = theme.DialogText;

            ApplyThemeToControls(Controls, theme);

            databaseNameTextBox.BackColor = theme.InputBackground;
            databaseNameTextBox.ForeColor = theme.InputText;
            databaseProviderComboBox.BackColor = theme.InputBackground;
            databaseProviderComboBox.ForeColor = theme.InputText;

            separator.BackColor = theme.Border;

            ApplyButtonTheme(okButton, theme);
            ApplyButtonTheme(cancelButton, theme);
        }

        private static void ApplyThemeToControls(Control.ControlCollection controls, VsTheme theme)
        {
            foreach (Control control in controls)
            {
                control.BackColor = theme.DialogBackground;
                control.ForeColor = theme.DialogText;

                var checkBox = control as CheckBox;
                if (checkBox != null)
                {
                    checkBox.UseVisualStyleBackColor = false;
                }

                if (control.HasChildren)
                {
                    ApplyThemeToControls(control.Controls, theme);
                }
            }
        }

        private static void ApplyButtonTheme(Button button, VsTheme theme)
        {
            button.FlatStyle = FlatStyle.Flat;
            button.UseVisualStyleBackColor = false;
            button.BackColor = theme.ButtonBackground;
            button.ForeColor = EnsureReadableTextColor(theme.ButtonText, theme.ButtonBackground);
            button.FlatAppearance.BorderColor = theme.ButtonBorder;
            button.FlatAppearance.MouseOverBackColor = theme.ButtonHoverBackground;
            button.FlatAppearance.MouseDownBackColor = theme.ButtonPressedBackground;
        }

        private static Color EnsureReadableTextColor(Color foreground, Color background)
        {
            if (ContrastRatio(foreground, background) >= 4.5)
            {
                return foreground;
            }

            return ContrastRatio(Color.Black, background) >= ContrastRatio(Color.White, background)
                ? Color.Black
                : Color.White;
        }

        private static double ContrastRatio(Color foreground, Color background)
        {
            var foregroundLuminance = RelativeLuminance(foreground);
            var backgroundLuminance = RelativeLuminance(background);
            var lighter = Math.Max(foregroundLuminance, backgroundLuminance);
            var darker = Math.Min(foregroundLuminance, backgroundLuminance);

            return (lighter + 0.05) / (darker + 0.05);
        }

        private static double RelativeLuminance(Color color)
        {
            return 0.2126 * Linearize(color.R) + 0.7152 * Linearize(color.G) + 0.0722 * Linearize(color.B);
        }

        private static double Linearize(byte channel)
        {
            var value = channel / 255.0;
            return value <= 0.03928 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);
        }

        private void UpdateProviderOptions()
        {
            if (UseSqlServer)
            {
                includePgAdminCheckBox.Checked = false;
                includePgAdminCheckBox.Enabled = false;
                return;
            }

            includePgAdminCheckBox.Enabled = true;
        }
    }

    internal sealed class VsTheme
    {
        private VsTheme(
            Color dialogBackground,
            Color dialogText,
            Color inputBackground,
            Color inputText,
            Color border,
            Color buttonBackground,
            Color buttonText,
            Color buttonBorder,
            Color buttonHoverBackground,
            Color buttonPressedBackground)
        {
            DialogBackground = dialogBackground;
            DialogText = dialogText;
            InputBackground = inputBackground;
            InputText = inputText;
            Border = border;
            ButtonBackground = buttonBackground;
            ButtonText = buttonText;
            ButtonBorder = buttonBorder;
            ButtonHoverBackground = buttonHoverBackground;
            ButtonPressedBackground = buttonPressedBackground;
        }

        public Color DialogBackground { get; private set; }
        public Color DialogText { get; private set; }
        public Color InputBackground { get; private set; }
        public Color InputText { get; private set; }
        public Color Border { get; private set; }
        public Color ButtonBackground { get; private set; }
        public Color ButtonText { get; private set; }
        public Color ButtonBorder { get; private set; }
        public Color ButtonHoverBackground { get; private set; }
        public Color ButtonPressedBackground { get; private set; }

        public static VsTheme Current
        {
            get
            {
                return new VsTheme(
                    GetThemedColor("DialogColorKey", SystemColors.Window),
                    GetThemedColor("DialogTextColorKey", SystemColors.ControlText),
                    GetThemedColor("ComboBoxBackgroundColorKey", SystemColors.Window),
                    GetThemedColor("ComboBoxTextColorKey", SystemColors.WindowText),
                    GetThemedColor("PanelSeparatorColorKey", SystemColors.ControlDark),
                    GetThemedColor("ButtonColorKey", SystemColors.Control),
                    GetThemedColor("ButtonTextColorKey", SystemColors.ControlText),
                    GetThemedColor("ButtonBorderColorKey", SystemColors.ActiveBorder),
                    GetThemedColor("ButtonMouseOverColorKey", SystemColors.ControlLight),
                    GetThemedColor("ButtonMouseDownColorKey", SystemColors.ControlDark));
            }
        }

        private static Color GetThemedColor(string keyPropertyName, Color fallback)
        {
            try
            {
                var environmentColorsType = Type.GetType("Microsoft.VisualStudio.PlatformUI.EnvironmentColors, Microsoft.VisualStudio.Shell.15.0", false);
                var colorThemeType = Type.GetType("Microsoft.VisualStudio.PlatformUI.VSColorTheme, Microsoft.VisualStudio.Shell.15.0", false);

                if (environmentColorsType == null || colorThemeType == null)
                {
                    return fallback;
                }

                var keyProperty = environmentColorsType.GetProperty(keyPropertyName, BindingFlags.Public | BindingFlags.Static);
                var getColorMethod = colorThemeType.GetMethod("GetThemedColor", BindingFlags.Public | BindingFlags.Static);

                if (keyProperty == null || getColorMethod == null)
                {
                    return fallback;
                }

                var key = keyProperty.GetValue(null, null);
                var themedColor = getColorMethod.Invoke(null, new[] { key });
                return themedColor is Color ? (Color)themedColor : fallback;
            }
            catch
            {
                return fallback;
            }
        }
    }
}
'@

    Write-Utf8NoBom (Join-Path $WizardDirectory "EnhancedAspireStarterWizard.cs") $wizardCode
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

function Set-ZipTextEntry(
    [System.IO.Compression.ZipArchive] $Zip,
    [string] $EntryName,
    [string] $Content
) {
    $existingEntry = $Zip.GetEntry($EntryName)
    if ($existingEntry) {
        $existingEntry.Delete()
    }

    $entry = $Zip.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        try {
            $writer.Write($Content)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ZipTextEntry(
    [System.IO.Compression.ZipArchive] $Zip,
    [string] $EntryName
) {
    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry) {
        return $null
    }

    $stream = $entry.Open()
    try {
        $reader = [System.IO.StreamReader]::new($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Add-TemplateZipToVsix(
    [string] $VsixPath,
    [string] $TemplateZipPath,
    [string] $EntryName
) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::Open($VsixPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $existingTemplateEntry = $zip.GetEntry($EntryName)
        if ($existingTemplateEntry) {
            $existingTemplateEntry.Delete()
        }

        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $TemplateZipPath,
            $EntryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null

        [xml] $contentTypes = Get-ZipTextEntry $zip "[Content_Types].xml"
        $contentTypesNamespace = $contentTypes.Types.NamespaceURI
        $zipContentType = $contentTypes.Types.Default | Where-Object { $_.Extension -eq "zip" } | Select-Object -First 1
        if (-not $zipContentType) {
            $zipContentType = $contentTypes.CreateElement("Default", $contentTypesNamespace)
            $zipContentType.SetAttribute("Extension", "zip")
            $zipContentType.SetAttribute("ContentType", "application/zip")
            $contentTypes.Types.AppendChild($zipContentType) | Out-Null
            Set-ZipTextEntry $zip "[Content_Types].xml" $contentTypes.OuterXml
        }

        $manifestJson = Get-ZipTextEntry $zip "manifest.json"
        if ($manifestJson) {
            $manifest = $manifestJson | ConvertFrom-Json
            $entryFileName = "/" + $EntryName
            $files = @($manifest.files)
            $hasEntry = $files | Where-Object { $_.fileName -eq $entryFileName } | Select-Object -First 1

            if (-not $hasEntry) {
                $files += [pscustomobject] @{
                    fileName = $entryFileName
                    sha256 = $null
                }

                $manifest.files = $files
            }

            if ($manifest.installSizes -and $manifest.installSizes.targetDrive) {
                $manifest.installSizes.targetDrive = [int64] $manifest.installSizes.targetDrive + (Get-Item -LiteralPath $TemplateZipPath).Length
            }

            Set-ZipTextEntry $zip "manifest.json" ($manifest | ConvertTo-Json -Depth 50 -Compress)
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
        $content = Convert-DotNetTemplateConditionDirectives $content
        $content = $content.Replace('const string SeedCatalogSampleDataValue = "true";', 'const string SeedCatalogSampleDataValue = "$ext_aspireadmin_seedcatalogsampledatavalue$";')
        $content = $content.Replace('const string SeedDevelopmentTestUsersValue = "true";', 'const string SeedDevelopmentTestUsersValue = "$ext_aspireadmin_seeddevelopmenttestusersvalue$";')
        $content = $content.Replace("f6e76cbf-2d79-4b8b-9023-113ac10e07f9", '$guid1$')
        $content = $content.Replace("vwzhang", '$registeredorganization$')
        $content = $content.Replace("starterDb", '$ext_safeprojectname$Db')
        $content = $content.Replace("starterdb", '$ext_aspireadmin_databasename$')
        $content = $content.Replace("starter.local", '$ext_safeprojectname$.local')
        $content = $content.Replace("starter-", '$ext_safeprojectname$-')
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

function Test-VendorTemplateFile([string] $RelativePath) {
    return $RelativePath -match '(^|\\)wwwroot\\lib\\'
}

function Add-DirectoryItemsXml(
    [System.Xml.XmlWriter] $Writer,
    [string] $CurrentDirectory,
    [string] $ProjectDirectory,
    [string] $ProjectName
) {
    $files = Get-ChildItem -LiteralPath $CurrentDirectory -File -Force |
        Where-Object {
            $_.Name -ne "$ProjectName.vstemplate" -and
            $_.Name -ne "$ProjectName.csproj"
        } |
        Sort-Object Name

    foreach ($file in $files) {
        $relativePath = Get-RelativePath $ProjectDirectory $file.FullName
        $targetFileName = $file.Name.Replace("Starter", '$ext_safeprojectname$')
        $replaceParameters = (Test-TextTemplateFile $file.FullName) -and -not (Test-VendorTemplateFile $relativePath)
        Add-ProjectItemXml $Writer $file.Name $targetFileName $replaceParameters
    }

    $directories = Get-ChildItem -LiteralPath $CurrentDirectory -Directory -Force |
        Where-Object {
            $_.Name -notin @("bin", "obj", ".git", ".vs", "_solution")
        } |
        Sort-Object Name

    foreach ($childDirectory in $directories) {
        $targetFolderName = $childDirectory.Name.Replace("Starter", '$ext_safeprojectname$')

        $Writer.WriteStartElement("Folder")
        $Writer.WriteAttributeString("Name", $childDirectory.Name)
        $Writer.WriteAttributeString("TargetFolderName", $targetFolderName)
        Add-DirectoryItemsXml $Writer $childDirectory.FullName $ProjectDirectory $ProjectName
        $Writer.WriteEndElement()
    }
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
        $writer.WriteElementString("DefaultName", $shortProjectName)
        $writer.WriteElementString("CreateInPlace", "true")
        $writer.WriteEndElement()

        $writer.WriteStartElement("TemplateContent")
        $writer.WriteStartElement("Project")
        $writer.WriteAttributeString("File", $projectFile)
        $writer.WriteAttributeString("TargetFileName", $targetProjectFile)
        $writer.WriteAttributeString("ReplaceParameters", "true")

        Add-DirectoryItemsXml $writer $ProjectDirectory $ProjectDirectory $ProjectName

        $writer.WriteEndElement()
        $writer.WriteEndElement()

        $writer.WriteStartElement("WizardExtension")
        $writer.WriteElementString("Assembly", "EnhancedAspireStarter.Wizard")
        $writer.WriteElementString("FullClassName", "EnhancedAspireStarter.VisualStudio.EnhancedAspireStarterWizard")
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
    <Description>Opinionated .NET Aspire starter with Blazor, Identity, PostgreSQL or SQL Server, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
    <ProjectType>CSharp</ProjectType>
    <LanguageTag>csharp</LanguageTag>
    <PlatformTag>windows</PlatformTag>
    <PlatformTag>linux</PlatformTag>
    <PlatformTag>macos</PlatformTag>
    <ProjectTypeTag>cloud</ProjectTypeTag>
    <ProjectTypeTag>web</ProjectTypeTag>
    <ProjectTypeTag>service</ProjectTypeTag>
    <ProjectTypeTag>Aspire</ProjectTypeTag>
    <ProjectTypeTag>Blazor</ProjectTypeTag>
    <ProjectTypeTag>.NET</ProjectTypeTag>
    <DefaultName>MyAspireAdmin</DefaultName>
    <CreateNewFolder>false</CreateNewFolder>
    <CreateInPlace>true</CreateInPlace>
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
  <WizardExtension>
    <Assembly>EnhancedAspireStarter.Wizard</Assembly>
    <FullClassName>EnhancedAspireStarter.VisualStudio.EnhancedAspireStarterWizard</FullClassName>
  </WizardExtension>
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
    <Description xml:space="preserve">Visual Studio project template for an enhanced Aspire starter with Blazor, Identity, PostgreSQL or SQL Server, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
    <MoreInfo>https://github.com/vwzhang/Starter.Template</MoreInfo>
    <License>Resources\LICENSE.txt</License>
    <ReleaseNotes>Resources\ReleaseNotes.txt</ReleaseNotes>
    <Tags>Aspire; .NET; Blazor; ASP.NET Core; Identity; PostgreSQL; SQL Server; Redis; pgAdmin; smtp4dev; Admin; Enhanced Aspire; Project Template</Tags>
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
    <Asset Type="Microsoft.VisualStudio.ProjectTemplate" Path="ProjectTemplates\CSharp" />
    <Asset Type="Microsoft.VisualStudio.Assembly" Path="EnhancedAspireStarter.Wizard.dll" AssemblyName="EnhancedAspireStarter.Wizard" />
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
    <ZipProject Include="ProjectTemplates\CSharp\Aspire\EnhancedAspireStarter\**\*">
      <RootPath>ProjectTemplates\CSharp\Aspire\EnhancedAspireStarter</RootPath>
      <Language>CSharp</Language>
      <OutputSubPath>Aspire</OutputSubPath>
    </ZipProject>
    <Content Include="Resources\LICENSE.txt" IncludeInVSIX="true" VSIXSubPath="Resources" />
    <Content Include="Resources\ReleaseNotes.txt" IncludeInVSIX="true" VSIXSubPath="Resources" />
    <Content Include="EnhancedAspireStarter.Wizard.dll" IncludeInVSIX="true" />
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
$wizardProjectRoot = Join-Path $vsixProjectRoot "Wizard"
$wizardBuildOutput = Join-Path $wizardProjectRoot "bin\Release\EnhancedAspireStarter.Wizard.dll"
$vsixProjectTemplateRoot = Join-Path $vsixProjectRoot "ProjectTemplates\CSharp\Aspire\EnhancedAspireStarter"
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

Convert-ToTemplateTokenizedFiles $templateRoot
Convert-VsixProjectFileConditionals $templateRoot
Write-RootTemplate (Join-Path $templateRoot "EnhancedAspireStarter.vstemplate")

$projectDescriptions = @{
    "Starter.ApiService" = "Minimal API backend with shared DTOs and selected database provider integration."
    "Starter.AppHost" = "Aspire AppHost that orchestrates PostgreSQL or SQL Server, Redis, pgAdmin, smtp4dev, API, migrations, and Blazor."
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
Copy-Item -LiteralPath $templateRoot -Destination $vsixProjectTemplateRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $templateSourcePath "LICENSE") -Destination (Join-Path $vsixProjectRoot "Resources\LICENSE.txt") -Force
Write-Utf8NoBom (Join-Path $vsixProjectRoot "Resources\ReleaseNotes.txt") "Enhanced Aspire Starter project template with Visual Studio options."
Write-WizardProjectFiles $wizardProjectRoot $visualStudioSdk.TemplateWizardInterfacePath $visualStudioSdk.EnvDtePath $visualStudioSdk.VisualStudioInteropPath

$wizardBuildArguments = @(
    (Join-Path $wizardProjectRoot "EnhancedAspireStarter.Wizard.csproj"),
    "/restore",
    "/p:Configuration=Release",
    "/v:minimal"
)

& $visualStudioSdk.MSBuildPath @wizardBuildArguments
if ($LASTEXITCODE -ne 0) {
    throw "Wizard build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $wizardBuildOutput)) {
    throw "Wizard build completed but output was not found: $wizardBuildOutput"
}

Copy-Item -LiteralPath $wizardBuildOutput -Destination (Join-Path $vsixProjectRoot "EnhancedAspireStarter.Wizard.dll") -Force
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
Add-TemplateZipToVsix $vsixPath $templateZip "ProjectTemplates/CSharp/Aspire/EnhancedAspireStarter.zip"

Write-Host "Project template zip: $templateZip"
Write-Host "VSIX package: $vsixPath"
