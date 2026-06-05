# Visual Studio VSIX

This folder builds a Visual Studio Marketplace package for the Aspire Admin Starter template.

The VSIX build script converts the synchronized template source into a Visual Studio multi-project `.vstemplate` package and wraps it in a VSIX for Marketplace distribution.

The NuGet `dotnet new` package remains available for scripted generation. Avoid installing the NuGet template and the VSIX at the same time on the same development machine, because Visual Studio 2026 can surface both providers and show two similar `Aspire Admin Starter` entries.

The VSIX shows an options page after Create with the same major options as the `dotnet new` package: database provider, database name, pgAdmin, smtp4dev, seed users, and seed sample data.

## Build

Requires Visual Studio with the Visual Studio extension development workload.

You can open `EnhancedAspireStarter.VisualStudio.slnx` in Visual Studio and build the solution. The build project calls `Build-Vsix.ps1` and writes the VSIX to the shared artifacts folder.

Command-line build:

```powershell
.\visualstudio\Build-Vsix.ps1
```

Or through the Visual Studio build solution:

```powershell
dotnet build .\visualstudio\EnhancedAspireStarter.VisualStudio.slnx
```

Pass `/p:VisualStudioVsixVersion=0.1.25` when you want to build a one-off version without changing script defaults.

Output:

```text
artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.37.vsix
```

Double-click the VSIX to install it locally. Restart Visual Studio, then search for `Aspire Admin Starter` in the New Project dialog.

The database provider dropdown supports PostgreSQL and SQL Server. Selecting SQL Server disables pgAdmin because pgAdmin only applies to PostgreSQL.

After project creation, the wizard cleans provider-specific template blocks and sets the generated AppHost project as the startup project.

If two similar template entries appear, or if an older template name still appears, close Visual Studio and clear the local VS template cache:

```powershell
dotnet new uninstall Vwzhang.AspireAdminStarter.Templates
.\visualstudio\Clear-VisualStudioTemplateCache.ps1
```

Then install the latest VSIX again and restart Visual Studio. This removes stale per-user VSIX folders and Visual Studio Template Cache entries for this template only. The uninstall command removes CLI template packages that can appear in Visual Studio as a separate `.NET Core Template Provider` entry.

## Publish

Marketplace publishing requires a Visual Studio Marketplace publisher and a personal access token.

```powershell
$env:VS_MARKETPLACE_PAT = "<token>"
.\visualstudio\Publish-Marketplace.ps1
```

The publish script finds `VsixPublisher.exe` through Visual Studio SDK installation metadata. Keep the PAT out of source control and terminal logs.

## Maintenance

After changing the source starter app:

```powershell
.\scripts\Update-Template.ps1 -SourceRepository C:\Aspire\Starter -TemplateVersion 0.1.37
```

Use the generated app's `*.Shared\TemplateInfo.cs` file to confirm which template version Visual Studio used.
