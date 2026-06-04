# Aspire Admin Starter Template

![.NET](https://img.shields.io/badge/.NET-10.0-512BD4)
![Aspire](https://img.shields.io/badge/Aspire-13.4-5C2D91)
![Template](https://img.shields.io/badge/template-dotnet%20new-0E7C7B)
![Visual Studio](https://img.shields.io/badge/Visual%20Studio-VSIX-5C2D91)
![License](https://img.shields.io/badge/license-MIT-green)

Installable templates for creating a polished .NET 10 Aspire admin application foundation with Blazor, ASP.NET Core Identity, PostgreSQL, Redis, pgAdmin, smtp4dev, a migration service, admin modules, system settings, shared DTOs, and a database-backed CRUD sample.

Use the CLI template when you want options. Use the VSIX when you want a Visual Studio New Project experience with the complete default starter.

## What It Creates

| Area | Generated foundation |
| --- | --- |
| Aspire | AppHost with PostgreSQL 18, Redis, pgAdmin, smtp4dev, API, Web, and migrations |
| Web | Blazor Web App, MudBlazor shell, app bar login state, admin/dev navigation |
| Identity | Seeded admin/manager/user accounts, roles, permissions, self registration, forgot password |
| Admin | Dashboard, users, roles, permissions, features, system configuration |
| Data | EF Core migrations, PostgreSQL connection, API-owned Catalog sample |
| Email | Runtime SMTP settings and local smtp4dev capture |
| Quality | Restore/build-ready solution and Aspire integration smoke test |

## Build The Package

```powershell
dotnet pack
```

Current local package:

```text
bin\Release\Vwzhang.EnhancedAspireStarter.Templates.0.1.14.nupkg
```

## Install Locally

```powershell
dotnet new install .\bin\Release\Vwzhang.EnhancedAspireStarter.Templates.0.1.14.nupkg
```

Confirm the template is visible:

```powershell
dotnet new aspire-admin-starter --help
```

## Create A New App

```powershell
mkdir C:\Code\AcmeOps
cd C:\Code\AcmeOps
dotnet new aspire-admin-starter -n AcmeOps
dotnet build AcmeOps.slnx
aspire start --apphost AcmeOps.AppHost\AcmeOps.AppHost.csproj
```

The template writes the solution file and all project folders directly into the current directory. There is no extra solution folder inside `C:\Code\AcmeOps`.

The generated app opens with:

- Workspace dashboard at `/`
- Admin login at `/admin/login`
- Catalog CRUD sample at `/dev/catalog`
- pgAdmin at `http://localhost:5050` when included
- smtp4dev at `http://localhost:5080` when included

## Template Options

```powershell
dotnet new aspire-admin-starter `
  -n AcmeOps `
  --database-name acmeopsdb `
  --include-pgadmin true `
  --include-smtp4dev true `
  --seed-users true `
  --seed-sample-data true
```

| Option | Default | Purpose |
| --- | --- | --- |
| `--database-name` | `<project-name>db` | PostgreSQL database and connection string name |
| `--include-pgadmin` | `true` | Include local pgAdmin for inspecting PostgreSQL |
| `--include-smtp4dev` | `true` | Include local email capture for account flows |
| `--seed-users` | `true` | Seed admin, manager, and user test accounts |
| `--seed-sample-data` | `true` | Seed catalog categories and products |

Useful examples:

```powershell
mkdir C:\Code\BackOffice; cd C:\Code\BackOffice
dotnet new aspire-admin-starter -n BackOffice --database-name backoffice

mkdir C:\Code\LeanApi; cd C:\Code\LeanApi
dotnet new aspire-admin-starter -n LeanApi --include-pgadmin false --include-smtp4dev false

mkdir C:\Code\CleanStart; cd C:\Code\CleanStart
dotnet new aspire-admin-starter -n CleanStart --seed-users false --seed-sample-data false
```

## Default Test Accounts

When `--seed-users true` is used:

| Email | Role | Password |
| --- | --- | --- |
| `admin@<project>.local` | Administrator | `Happy1..` |
| `manager@<project>.local` | Manager | `Happy1..` |
| `user@<project>.local` | User | `Happy1..` |

## Visual Studio VSIX

Build the VSIX:

```powershell
.\visualstudio\Build-Vsix.ps1
```

Output:

```text
artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.14.vsix
```

Install it, restart Visual Studio, then search for `Aspire Admin Starter` in the New Project dialog. After you click Create, the template displays an options page for database name, pgAdmin, smtp4dev, and seed data.

The VSIX currently generates the complete default starter. The CLI package is the best path when you need the generation options.

## Maintainer Workflow

After changing the source starter app, run:

```powershell
.\scripts\Update-Template.ps1 -SourceRepository C:\Aspire\Starter -TemplateVersion 0.1.14
```

The helper:

- Syncs source into `templates\enhanced-aspire-starter`
- Converts the source README into a generated-project README
- Updates `Starter.Shared.TemplateInfo.Version`
- Updates package and VSIX version references
- Runs `dotnet pack`
- Builds the Visual Studio VSIX

## Verification

Recommended checks before publishing a new template version:

```powershell
dotnet new install .\bin\Release\Vwzhang.EnhancedAspireStarter.Templates.0.1.14.nupkg --force
mkdir C:\Temp\SmokeApp
cd C:\Temp\SmokeApp
dotnet new aspire-admin-starter -n SmokeApp --force
dotnet build C:\Temp\SmokeApp\SmokeApp.slnx
mkdir C:\Temp\SlimApp
cd C:\Temp\SlimApp
dotnet new aspire-admin-starter -n SlimApp --include-pgadmin false --include-smtp4dev false --seed-users false --seed-sample-data false --force
dotnet build C:\Temp\SlimApp\SlimApp.slnx
```

## Links

- Source app: `https://github.com/vwzhang/Starter`
- Template repo: `https://github.com/vwzhang/Starter.Template`

## License

MIT
