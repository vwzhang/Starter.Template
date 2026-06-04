# Visual Studio VSIX

This folder builds a Visual Studio Marketplace package for the Aspire Admin Starter template.

The NuGet `dotnet new` package remains the primary template source. The VSIX build script converts the synchronized template source into a Visual Studio multi-project `.vstemplate` package and wraps it in a VSIX.

The VSIX shows an options page after Create with the same major options as the `dotnet new` package: database provider, database name, pgAdmin, smtp4dev, seed users, and seed sample data.

## Build

Requires Visual Studio with the Visual Studio extension development workload.

```powershell
.\visualstudio\Build-Vsix.ps1
```

Output:

```text
artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.16.vsix
```

Double-click the VSIX to install it locally. Restart Visual Studio, then search for `Aspire Admin Starter` in the New Project dialog.

The database provider dropdown supports PostgreSQL and SQL Server. Selecting SQL Server disables pgAdmin because pgAdmin only applies to PostgreSQL.

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
.\scripts\Update-Template.ps1 -SourceRepository C:\Aspire\Starter -TemplateVersion 0.1.16
```

Use the generated app's `*.Shared\TemplateInfo.cs` file to confirm which template version Visual Studio used.
