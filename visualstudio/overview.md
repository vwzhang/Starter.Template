# Aspire Admin Starter

Start a real .NET Aspire application without spending the first day wiring infrastructure.

Aspire Admin Starter is an opinionated Visual Studio project template for internal tools, admin portals, and full-stack line-of-business apps.

## Included

- .NET Aspire AppHost with PostgreSQL or SQL Server, Redis, optional pgAdmin, optional smtp4dev, API, migrations, and Blazor frontend
- Blazor Web App with MudBlazor and interactive server rendering
- ASP.NET Core Identity with seeded admin, manager, and user accounts
- Configurable registration, email confirmation, forgot password, and SMTP settings
- Admin module with users, roles, permissions, and system configuration
- Shared DTO project for API and frontend contracts
- Dev pages with a CRUD sample wired through the selected database provider and the Minimal API
- Aspire integration test starter

## After Creating A Project

Build the generated solution, then run the Aspire AppHost:

```powershell
dotnet build
aspire start --apphost .\MyStarter.AppHost\MyStarter.AppHost.csproj
```

Default test password:

```text
Happy1..
```

The generated app can capture local email with smtp4dev and includes pgAdmin for PostgreSQL inspection when those options are enabled.

## Other Install Options

The same template is also available as a `dotnet new` template package from the project repository:

```powershell
dotnet new install Vwzhang.AspireAdminStarter.Templates
dotnet new aspire-admin-starter -n MyStarter
```

Repository: https://github.com/vwzhang/Starter.Template
