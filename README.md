# Enhanced Aspire Starter Template

Installable `dotnet new` template package for the enhanced Aspire starter.

## Build The Template Package

```powershell
dotnet pack
```

## Install Locally

```powershell
dotnet new install .\bin\Release\Vwzhang.EnhancedAspireStarter.Templates.0.1.10.nupkg
```

## Create A New App

```powershell
dotnet new enhanced-aspire-starter -n MyStarter -o C:\Temp\MyStarter
dotnet build C:\Temp\MyStarter\MyStarter.slnx
```

Useful options:

```powershell
dotnet new enhanced-aspire-starter `
  -n MyStarter `
  -o C:\Temp\MyStarter `
  --database-name mystarterdb `
  --include-pgadmin true `
  --include-smtp4dev true `
  --seed-users true `
  --seed-sample-data true
```

| Option | Default | Purpose |
| --- | --- | --- |
| `--database-name` | `<project-name>db` | PostgreSQL database and connection string name |
| `--include-pgadmin` | `true` | Include local pgAdmin |
| `--include-smtp4dev` | `true` | Include local email capture |
| `--seed-users` | `true` | Seed admin, manager, and user test accounts |
| `--seed-sample-data` | `true` | Seed catalog categories and products |

Run the generated Aspire app:

```powershell
cd C:\Temp\MyStarter
aspire start --apphost MyStarter.AppHost\MyStarter.AppHost.csproj
```

The generated app includes Blazor, ASP.NET Core Identity, PostgreSQL, Redis, pgAdmin, smtp4dev, a migration service, admin modules, system settings, and a CRUD sample.

## Build The Visual Studio VSIX

```powershell
.\visualstudio\Build-Vsix.ps1
```

This produces `artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.10.vsix` for local install or Visual Studio Marketplace upload.

The VSIX currently generates the complete default starter. Use the `dotnet new` package when you need the template options above.

## Template Maintenance

After updating the source starter app, run the release helper from this repository:

```powershell
.\scripts\Update-Template.ps1 -SourceRepository C:\Aspire\Starter -TemplateVersion 0.1.10
```

The helper syncs `templates\enhanced-aspire-starter`, preserves the generated `TemplateInfo.cs` version marker, updates package/VSIX version references, runs `dotnet pack`, and builds the Visual Studio VSIX.
