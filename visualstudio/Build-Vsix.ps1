param(
    [string] $TemplateSource = (Join-Path $PSScriptRoot "..\templates\enhanced-aspire-starter"),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot "..\artifacts\vsix"),
    [string] $Version = "0.1.15",
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
    <AssemblyName>AspireAdminStarter.Wizard</AssemblyName>
    <RootNamespace>AspireAdminStarter.VisualStudio</RootNamespace>
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

    Write-Utf8NoBom (Join-Path $WizardDirectory "AspireAdminStarter.Wizard.csproj") $projectFile

    $wizardCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using EnvDTE;
using Microsoft.VisualStudio.TemplateWizard;

namespace AspireAdminStarter.VisualStudio
{
    public sealed class AspireAdminStarterWizard : IWizard
    {
        private bool useSqlServer;

        public void RunStarted(
            object automationObject,
            Dictionary<string, string> replacementsDictionary,
            WizardRunKind runKind,
            object[] customParams)
        {
            var projectName = GetReplacement(replacementsDictionary, "$safeprojectname$", "MyAspireAdmin");
            var defaultDatabaseName = ToResourceName(projectName) + "db";
            Application.EnableVisualStyles();
            var owner = OwnerWindow.FromAutomationObject(automationObject);

            using (var form = new OptionsForm(defaultDatabaseName))
            {
                var result = owner == null ? form.ShowDialog() : form.ShowDialog(owner);
                if (result != DialogResult.OK)
                {
                    throw new WizardCancelledException("Aspire Admin Starter creation was canceled.");
                }

                useSqlServer = form.UseSqlServer;
                SetReplacement(replacementsDictionary, "$aspireadmin_databaseprovider$", form.DatabaseProvider);
                SetReplacement(replacementsDictionary, "$aspireadmin_usepostgresql$", ToTemplateBoolean(form.UsePostgreSql));
                SetReplacement(replacementsDictionary, "$aspireadmin_usesqlserver$", ToTemplateBoolean(form.UseSqlServer));
                SetReplacement(replacementsDictionary, "$aspireadmin_databasename$", form.DatabaseName);
                SetReplacement(replacementsDictionary, "$aspireadmin_includepgadmin$", ToTemplateBoolean(form.IncludePgAdmin));
                SetReplacement(replacementsDictionary, "$aspireadmin_includepgadminforpostgresql$", ToTemplateBoolean(form.IncludePgAdminForPostgreSql));
                SetReplacement(replacementsDictionary, "$aspireadmin_includesmtp4dev$", ToTemplateBoolean(form.IncludeSmtp4dev));
                SetReplacement(replacementsDictionary, "$aspireadmin_seedcatalogsampledatavalue$", form.SeedSampleData ? "true" : "false");
                SetReplacement(replacementsDictionary, "$aspireadmin_seeddevelopmenttestusersvalue$", form.SeedUsers ? "true" : "false");
            }
        }

        public void ProjectFinishedGenerating(Project project)
        {
        }

        public void ProjectItemFinishedGenerating(ProjectItem projectItem)
        {
        }

        public bool ShouldAddProjectItem(string filePath)
        {
            var normalizedPath = (filePath ?? string.Empty).Replace('/', '\\');

            if (normalizedPath.IndexOf("\\Migrations.SqlServer\\", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return useSqlServer;
            }

            if (useSqlServer && normalizedPath.IndexOf("\\Migrations\\", StringComparison.OrdinalIgnoreCase) >= 0)
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
            Text = "Aspire Admin Starter options";
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
                Text = "Create",
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
                    "Aspire Admin Starter",
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
            button.ForeColor = theme.ButtonText;
            button.FlatAppearance.BorderColor = theme.ButtonBorder;
            button.FlatAppearance.MouseOverBackColor = theme.ButtonHoverBackground;
            button.FlatAppearance.MouseDownBackColor = theme.ButtonPressedBackground;
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

    Write-Utf8NoBom (Join-Path $WizardDirectory "AspireAdminStarterWizard.cs") $wizardCode
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
        $writer.WriteElementString("Name", "Aspire Admin Starter $shortProjectName")
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
    <Name>Aspire Admin Starter</Name>
    <Description>Opinionated .NET Aspire admin starter with Blazor, Identity, PostgreSQL or SQL Server, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
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
    <Assembly>AspireAdminStarter.Wizard</Assembly>
    <FullClassName>AspireAdminStarter.VisualStudio.AspireAdminStarterWizard</FullClassName>
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
    <DisplayName>Aspire Admin Starter</DisplayName>
    <Description xml:space="preserve">Visual Studio project template for an Aspire admin starter with Blazor, Identity, PostgreSQL or SQL Server, Redis, pgAdmin, smtp4dev, migrations, admin modules, system settings, and a CRUD sample.</Description>
    <MoreInfo>https://github.com/vwzhang/Starter.Template</MoreInfo>
    <License>Resources\LICENSE.txt</License>
    <ReleaseNotes>Resources\ReleaseNotes.txt</ReleaseNotes>
    <Tags>Aspire; .NET; Blazor; ASP.NET Core; Identity; PostgreSQL; SQL Server; Redis; pgAdmin; smtp4dev; Admin; Project Template</Tags>
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
    <Asset Type="Microsoft.VisualStudio.Assembly" Path="AspireAdminStarter.Wizard.dll" AssemblyName="AspireAdminStarter.Wizard" />
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
    <Content Include="AspireAdminStarter.Wizard.dll" IncludeInVSIX="true" />
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
$wizardBuildOutput = Join-Path $wizardProjectRoot "bin\Release\AspireAdminStarter.Wizard.dll"
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
Write-Utf8NoBom (Join-Path $vsixProjectRoot "Resources\ReleaseNotes.txt") "Aspire Admin Starter project template with Visual Studio options."
Write-WizardProjectFiles $wizardProjectRoot $visualStudioSdk.TemplateWizardInterfacePath $visualStudioSdk.EnvDtePath $visualStudioSdk.VisualStudioInteropPath

$wizardBuildArguments = @(
    (Join-Path $wizardProjectRoot "AspireAdminStarter.Wizard.csproj"),
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

Copy-Item -LiteralPath $wizardBuildOutput -Destination (Join-Path $vsixProjectRoot "AspireAdminStarter.Wizard.dll") -Force
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
