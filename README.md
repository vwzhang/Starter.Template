# Enhanced Aspire Starter Template

Installable `dotnet new` template package for the enhanced Aspire starter.

## Build The Template Package

```powershell
dotnet pack
```

## Install Locally

```powershell
dotnet new install .\bin\Release\Vwzhang.EnhancedAspireStarter.Templates.0.1.6.nupkg
```

## Create A New App

```powershell
dotnet new enhanced-aspire-starter -n MyStarter -o C:\Temp\MyStarter
dotnet build C:\Temp\MyStarter\MyStarter.slnx
```

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

This produces `artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.6.vsix` for local install or Visual Studio Marketplace upload.

## Template Maintenance

Use `scripts\Sync-TemplateSource.ps1` from this repository after updating the source starter app.
