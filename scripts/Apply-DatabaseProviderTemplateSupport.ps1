param(
    [string] $TemplateContent = "C:\Aspire\Starter.Template\templates\enhanced-aspire-starter"
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Read-NormalizedText([string] $Path) {
    [System.IO.File]::ReadAllText((Resolve-FullPath $Path)).Replace("`r`n", "`n")
}

function Write-Utf8NoBom([string] $Path, [string] $Content) {
    [System.IO.File]::WriteAllText((Resolve-FullPath $Path), $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-RelativePath([string] $BasePath, [string] $Path) {
    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/") + "\"
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.StartsWith($baseFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($baseFullPath.Length)
    }

    return $Path
}

function Replace-Required(
    [string] $Path,
    [string] $Search,
    [string] $Replacement,
    [string] $Marker
) {
    $content = Read-NormalizedText $Path

    if ($content.Contains($Marker)) {
        return
    }

    if (-not $content.Contains($Search)) {
        throw "Unable to apply database provider template support. Expected text was not found in $Path"
    }

    Write-Utf8NoBom $Path $content.Replace($Search, $Replacement)
}

function Copy-OverlayContent([string] $OverlayRoot, [string] $TargetRoot) {
    if (-not (Test-Path -LiteralPath $OverlayRoot)) {
        throw "SQL Server migrations overlay was not found: $OverlayRoot"
    }

    Remove-Item -LiteralPath (Join-Path $TargetRoot "Starter.Web\Data\Migrations.SqlServer") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $TargetRoot "Starter.ApiService\Data\Migrations.SqlServer") -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($file in Get-ChildItem -LiteralPath $OverlayRoot -Recurse -File) {
        $relativePath = Get-RelativePath $OverlayRoot $file.FullName
        $targetPath = Join-Path $TargetRoot $relativePath
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($targetPath)) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
    }
}

$templateRoot = Resolve-FullPath $TemplateContent
$repoRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$overlayRoot = Join-Path $repoRoot "overlays\sqlserver-migrations"

Copy-OverlayContent $overlayRoot $templateRoot

$appHostPath = Join-Path $templateRoot "Starter.AppHost\AppHost.cs"
$appHostSearch = @'
//#if (includePgAdmin)
const string PgAdminImageTag = "9.14.0";
const string PgAdminDefaultEmail = "admin@domain.com";
const string PgAdminDefaultPassword = "Happy1..";
//#endif

// PostgreSQL 18 server with a persistent data volume.
var postgres = builder.AddPostgres("postgres")
    .WithImageTag("18")
    .WithDataVolume();

//#if (includePgAdmin)
postgres.WithPgAdmin(pgAdmin =>
{
    pgAdmin
        .WithImageTag(PgAdminImageTag)
        .WithEnvironment("PGADMIN_DEFAULT_EMAIL", PgAdminDefaultEmail)
        .WithEnvironment("PGADMIN_DEFAULT_PASSWORD", PgAdminDefaultPassword)
        .WithEnvironment("PGADMIN_CONFIG_SERVER_MODE", "False")
        .WithEnvironment("PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED", "False")
        // Bind directly because pgAdmin's gunicorn responses can trip the Aspire proxy health check.
        .WithHttpEndpoint(targetPort: 80, name: "http", isProxied: false)
        .WaitFor(postgres);

    foreach (var healthCheck in pgAdmin.Resource.Annotations.OfType<HealthCheckAnnotation>().ToArray())
    {
        pgAdmin.Resource.Annotations.Remove(healthCheck);
    }
}, "pgadmin");
//#endif

// Shared "starter" database consumed by both the API service and the web frontend.
var starterDb = postgres.AddDatabase("starterdb");
'@
$appHostReplacement = @'
//#if (includePgAdminForPostgreSql)
const string PgAdminImageTag = "9.14.0";
const string PgAdminDefaultEmail = "admin@domain.com";
const string PgAdminDefaultPassword = "Happy1..";
//#endif

//#if (usePostgreSql)
// PostgreSQL 18 server with a persistent data volume.
var postgres = builder.AddPostgres("postgres")
    .WithImageTag("18")
    .WithDataVolume();

//#if (includePgAdminForPostgreSql)
postgres.WithPgAdmin(pgAdmin =>
{
    pgAdmin
        .WithImageTag(PgAdminImageTag)
        .WithEnvironment("PGADMIN_DEFAULT_EMAIL", PgAdminDefaultEmail)
        .WithEnvironment("PGADMIN_DEFAULT_PASSWORD", PgAdminDefaultPassword)
        .WithEnvironment("PGADMIN_CONFIG_SERVER_MODE", "False")
        .WithEnvironment("PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED", "False")
        // Bind directly because pgAdmin's gunicorn responses can trip the Aspire proxy health check.
        .WithHttpEndpoint(targetPort: 80, name: "http", isProxied: false)
        .WaitFor(postgres);

    foreach (var healthCheck in pgAdmin.Resource.Annotations.OfType<HealthCheckAnnotation>().ToArray())
    {
        pgAdmin.Resource.Annotations.Remove(healthCheck);
    }
}, "pgadmin");
//#endif

// Shared "starter" database consumed by the API service and web frontend.
var starterDb = postgres.AddDatabase("starterdb");
//#endif

//#if (useSqlServer)
// SQL Server container with a persistent data volume.
var sqlServer = builder.AddSqlServer("sqlserver")
    .WithDataVolume();

// Shared "starter" database consumed by the API service and web frontend.
var starterDb = sqlServer.AddDatabase("starterdb");
//#endif
'@
Replace-Required $appHostPath $appHostSearch $appHostReplacement "useSqlServer"

Replace-Required `
    (Join-Path $templateRoot "Starter.AppHost\Starter.AppHost.csproj") `
    '    <PackageReference Include="Aspire.Hosting.PostgreSQL" Version="13.4.0" />' `
    @'
    <!--#if (usePostgreSql) -->
    <PackageReference Include="Aspire.Hosting.PostgreSQL" Version="13.4.0" />
    <!--#endif -->
    <!--#if (useSqlServer) -->
    <PackageReference Include="Aspire.Hosting.SqlServer" Version="13.4.0" />
    <!--#endif -->
'@ `
    "Aspire.Hosting.SqlServer"

Replace-Required `
    (Join-Path $templateRoot "Starter.ApiService\Starter.ApiService.csproj") `
    '    <PackageReference Include="Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" Version="13.4.0" />' `
    @'
    <!--#if (usePostgreSql) -->
    <PackageReference Include="Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" Version="13.4.0" />
    <!--#endif -->
    <!--#if (useSqlServer) -->
    <PackageReference Include="Aspire.Microsoft.EntityFrameworkCore.SqlServer" Version="13.4.0" />
    <!--#endif -->
'@ `
    "Aspire.Microsoft.EntityFrameworkCore.SqlServer"

Replace-Required `
    (Join-Path $templateRoot "Starter.MigrationService\Starter.MigrationService.csproj") `
    '    <PackageReference Include="Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" Version="13.4.0" />' `
    @'
    <!--#if (usePostgreSql) -->
    <PackageReference Include="Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" Version="13.4.0" />
    <!--#endif -->
    <!--#if (useSqlServer) -->
    <PackageReference Include="Aspire.Microsoft.EntityFrameworkCore.SqlServer" Version="13.4.0" />
    <!--#endif -->
'@ `
    "Aspire.Microsoft.EntityFrameworkCore.SqlServer"

Replace-Required `
    (Join-Path $templateRoot "Starter.Web\Starter.Web.csproj") `
    '    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.2" />' `
    @'
    <!--#if (usePostgreSql) -->
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.2" />
    <!--#endif -->
    <!--#if (useSqlServer) -->
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.0.8" />
    <!--#endif -->
'@ `
    "Microsoft.EntityFrameworkCore.SqlServer"

Replace-Required `
    (Join-Path $templateRoot "Starter.ApiService\Program.cs") `
    'builder.AddNpgsqlDbContext<CatalogDbContext>("starterdb");' `
    @'
//#if (usePostgreSql)
builder.AddNpgsqlDbContext<CatalogDbContext>("starterdb");
//#endif
//#if (useSqlServer)
builder.AddSqlServerDbContext<CatalogDbContext>("starterdb");
//#endif
'@ `
    "AddSqlServerDbContext<CatalogDbContext>"

Replace-Required `
    (Join-Path $templateRoot "Starter.MigrationService\Program.cs") `
    @'
builder.AddNpgsqlDbContext<ApplicationDbContext>("starterdb");
builder.AddNpgsqlDbContext<CatalogDbContext>("starterdb");
'@ `
    @'
//#if (usePostgreSql)
builder.AddNpgsqlDbContext<ApplicationDbContext>("starterdb");
builder.AddNpgsqlDbContext<CatalogDbContext>("starterdb");
//#endif
//#if (useSqlServer)
builder.AddSqlServerDbContext<ApplicationDbContext>("starterdb");
builder.AddSqlServerDbContext<CatalogDbContext>("starterdb");
//#endif
'@ `
    "AddSqlServerDbContext<ApplicationDbContext>"

Replace-Required `
    (Join-Path $templateRoot "Starter.Web\Program.cs") `
    '    options.UseNpgsql(connectionString);' `
    @'
//#if (usePostgreSql)
    options.UseNpgsql(connectionString);
//#endif
//#if (useSqlServer)
    options.UseSqlServer(connectionString);
//#endif
'@ `
    "UseSqlServer(connectionString)"

$webFactorySearch = @'
    public ApplicationDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__starterdb")
            ?? "Host=localhost;Port=5432;Database=starterdb;Username=postgres;Password=postgres";

        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        return new ApplicationDbContext(options);
    }
'@
$webFactoryReplacement = @'
    public ApplicationDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__starterdb")
            ?? GetLocalConnectionString();

        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
//#if (usePostgreSql)
            .UseNpgsql(connectionString)
//#endif
//#if (useSqlServer)
            .UseSqlServer(connectionString)
//#endif
            .Options;

        return new ApplicationDbContext(options);
    }

    private static string GetLocalConnectionString()
    {
//#if (usePostgreSql)
        return "Host=localhost;Port=5432;Database=starterdb;Username=postgres;Password=postgres";
//#endif
//#if (useSqlServer)
        return "Server=localhost,1433;Database=starterdb;User Id=sa;Password=Happy1..;TrustServerCertificate=True";
//#endif
    }
'@
Replace-Required `
    (Join-Path $templateRoot "Starter.Web\Data\ApplicationDbContextFactory.cs") `
    $webFactorySearch `
    $webFactoryReplacement `
    "GetLocalConnectionString"

$catalogFactorySearch = @'
    public CatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__starterdb")
            ?? "Host=localhost;Port=5432;Database=starterdb;Username=postgres;Password=postgres";

        var options = new DbContextOptionsBuilder<CatalogDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        return new CatalogDbContext(options);
    }
'@
$catalogFactoryReplacement = @'
    public CatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__starterdb")
            ?? GetLocalConnectionString();

        var options = new DbContextOptionsBuilder<CatalogDbContext>()
//#if (usePostgreSql)
            .UseNpgsql(connectionString)
//#endif
//#if (useSqlServer)
            .UseSqlServer(connectionString)
//#endif
            .Options;

        return new CatalogDbContext(options);
    }

    private static string GetLocalConnectionString()
    {
//#if (usePostgreSql)
        return "Host=localhost;Port=5432;Database=starterdb;Username=postgres;Password=postgres";
//#endif
//#if (useSqlServer)
        return "Server=localhost,1433;Database=starterdb;User Id=sa;Password=Happy1..;TrustServerCertificate=True";
//#endif
    }
'@
Replace-Required `
    (Join-Path $templateRoot "Starter.ApiService\Data\CatalogDbContextFactory.cs") `
    $catalogFactorySearch `
    $catalogFactoryReplacement `
    "GetLocalConnectionString"

$homePath = Join-Path $templateRoot "Starter.Web\Components\Pages\Demo\Home.razor"
Replace-Required `
    $homePath `
    '                A ready-to-run .NET Aspire baseline with identity, admin modules, PostgreSQL, Redis, email capture, shared DTOs, migrations, and catalog CRUD.' `
    '                A ready-to-run .NET Aspire baseline with identity, admin modules, a database provider, Redis, email capture, shared DTOs, migrations, and catalog CRUD.' `
    "a database provider"

Replace-Required `
    $homePath `
    '                        The migration service owns schema setup and seed data while API and Web share PostgreSQL through Aspire service discovery.' `
    '                        The migration service owns schema setup and seed data while API and Web share the selected database through Aspire service discovery.' `
    "selected database"

Replace-Required `
    $homePath `
    @'
    private static readonly LocalService[] LocalServices =
    [
        new("pgAdmin", "Endpoint shown in Aspire Dashboard", Icons.Material.Filled.Storage),
        new("smtp4dev", "Endpoint shown in Aspire Dashboard", Icons.Material.Filled.MarkEmailRead),
    ];
'@ `
    @'
    private static readonly LocalService[] LocalServices =
    [
@*#if (includePgAdminForPostgreSql)*@
        new("pgAdmin", "Endpoint shown in Aspire Dashboard", Icons.Material.Filled.Storage),
@*#endif*@
@*#if (includeSmtp4dev)*@
        new("smtp4dev", "Endpoint shown in Aspire Dashboard", Icons.Material.Filled.MarkEmailRead),
@*#endif*@
    ];
'@ `
    "includePgAdminForPostgreSql"

Replace-Required `
    $homePath `
    '        new("Run the full stack", "Use Aspire AppHost to start PostgreSQL, Redis, pgAdmin, smtp4dev, API, Web, and migrations together."),' `
    '        new("Run the full stack", "Use Aspire AppHost to start the database, Redis, optional local tools, API, Web, and migrations together."),' `
    "optional local tools"

Replace-Required `
    $homePath `
    @'
        <MudItem xs="12" md="4">
            <MudPaper Class="pa-4 starter-card" Outlined="true">
                <MudStack Spacing="2">
                    <MudAvatar Color="Color.Info" Variant="Variant.Filled">
                        <MudIcon Icon="@Icons.Material.Filled.MarkEmailRead" />
                    </MudAvatar>
                    <MudText Typo="Typo.h6">Email without friction</MudText>
                    <MudText Typo="Typo.body2" Class="starter-muted">
                        smtp4dev captures account emails locally, while Admin/System holds SMTP settings for future production delivery.
                    </MudText>
                    <MudButton Href="/admin" Variant="Variant.Text" Color="Color.Primary" StartIcon="@Icons.Material.Filled.Settings">
                        Email settings
                    </MudButton>
                </MudStack>
            </MudPaper>
        </MudItem>
'@ `
    @'
@*#if (includeSmtp4dev)*@
        <MudItem xs="12" md="4">
            <MudPaper Class="pa-4 starter-card" Outlined="true">
                <MudStack Spacing="2">
                    <MudAvatar Color="Color.Info" Variant="Variant.Filled">
                        <MudIcon Icon="@Icons.Material.Filled.MarkEmailRead" />
                    </MudAvatar>
                    <MudText Typo="Typo.h6">Email without friction</MudText>
                    <MudText Typo="Typo.body2" Class="starter-muted">
                        smtp4dev captures account emails locally, while Admin/System holds SMTP settings for future production delivery.
                    </MudText>
                    <MudButton Href="/admin" Variant="Variant.Text" Color="Color.Primary" StartIcon="@Icons.Material.Filled.Settings">
                        Email settings
                    </MudButton>
                </MudStack>
            </MudPaper>
        </MudItem>
@*#endif*@
'@ `
    "@*#if (includeSmtp4dev)*@`n        <MudItem xs=`"12`" md=`"4`">"

Replace-Required `
    (Join-Path $templateRoot "Starter.Web\Components\Pages\Dev\Components.razor") `
    '        new("starterdb", "PostgreSQL database", "Healthy", "starterdb", Icons.Material.Filled.Storage, Color.Success),' `
    '        new("starterdb", "Application database", "Healthy", "starterdb", Icons.Material.Filled.Storage, Color.Success),' `
    "Application database"

$componentsPath = Join-Path $templateRoot "Starter.Web\Components\Pages\Dev\Components.razor"
Replace-Required `
    $componentsPath `
    '        new("smtp4dev", "Local email inbox", "Healthy", "Aspire endpoint", Icons.Material.Filled.MarkEmailRead, Color.Secondary),' `
    @'
@*#if (includeSmtp4dev)*@
        new("smtp4dev", "Local email inbox", "Healthy", "Aspire endpoint", Icons.Material.Filled.MarkEmailRead, Color.Secondary),
@*#endif*@
'@ `
    "@*#if (includeSmtp4dev)*@`n        new(`"smtp4dev`""

Replace-Required `
    $componentsPath `
    '        new("Email capture configured", "smtp4dev is wired through system configuration in Development.", Color.Info),' `
    @'
@*#if (includeSmtp4dev)*@
        new("Email capture configured", "smtp4dev is wired through system configuration in Development.", Color.Info),
@*#endif*@
'@ `
    "@*#if (includeSmtp4dev)*@`n        new(`"Email capture configured`""

$readmePath = Join-Path $templateRoot "README.md"
if (Test-Path -LiteralPath $readmePath) {
    $readme = Read-NormalizedText $readmePath
    $readme = $readme.Replace(
        "![PostgreSQL](https://img.shields.io/badge/Data-PostgreSQL%2018-336791)",
        "![Database](https://img.shields.io/badge/Data-PostgreSQL%20or%20SQL%20Server-336791)")
    $readme = $readme.Replace(
        "PostgreSQL, Redis, local email capture, migrations",
        "a database provider, Redis, optional local email capture, migrations")
    $readme = $readme.Replace(
        "PostgreSQL, Redis, migrations, local email capture",
        "a database provider, Redis, migrations, optional local email capture")
    $readme = $readme.Replace(
        "| Local orchestration | Aspire AppHost with PostgreSQL 18, Redis, pgAdmin, smtp4dev, API, Web, and migration service |",
        "| Local orchestration | Aspire AppHost with PostgreSQL or SQL Server, Redis, optional local tools, API, Web, and migration service |")
    $readme = $readme.Replace(
        "| Developer loop | Local email inbox, pgAdmin, Redis output cache, Aspire dashboard, smoke test |",
        "| Developer loop | Optional local tool UIs, Redis output cache, Aspire dashboard, smoke test |")
    $readme = $readme.Replace(
        '| pgAdmin | `pgadmin` endpoint in Aspire Dashboard |',
        '| pgAdmin | `pgadmin` endpoint in Aspire Dashboard when PostgreSQL pgAdmin is enabled |')
    $readme = $readme.Replace(
        '| smtp4dev inbox | `smtp4dev` endpoint in Aspire Dashboard |',
        '| smtp4dev inbox | `smtp4dev` endpoint in Aspire Dashboard when local email capture is enabled |')
    $readme = $readme.Replace(
        "    AppHost --> Postgres[`"PostgreSQL 18<br/>Identity, settings, catalog`"]",
        "    AppHost --> Database[`"Selected database<br/>Identity, settings, catalog`"]")
    $readme = $readme.Replace(
        "    Web --> Postgres`n    Api --> Postgres`n    Migrations --> Postgres",
        "    Web --> Database`n    Api --> Database`n    Migrations --> Database")
    $readme = $readme.Replace(
        "    AppHost --> PgAdmin[`"pgAdmin`"]`n    AppHost --> Smtp[`"smtp4dev`"]",
        "    AppHost --> Tools[`"Optional local tools<br/>pgAdmin, smtp4dev`"]")
    $readme = $readme.Replace(
        "    Web --> Smtp",
        "    Web --> Tools")
    $readme = $readme.Replace(
        "The default AppHost runs smtp4dev, so account email flows work without an external SMTP server.",
        "When smtp4dev is enabled, account email flows work locally without an external SMTP server.")
    $readme = $readme.Replace(
        "- SMTP host and port supplied by the Aspire smtp4dev resource",
        "- SMTP host and port can be supplied by the Aspire smtp4dev resource")
    $readme = $readme.Replace(
        "- Email delivery enabled through smtp4dev",
        "- Optional local email capture through smtp4dev")
    $readme = $readme.Replace(
        "Open the `smtp4dev` endpoint from the Aspire Dashboard to inspect captured messages.",
        "Open the `smtp4dev` endpoint from the Aspire Dashboard when local email capture is enabled to inspect captured messages.")
    $readme = $readme.Replace(
        '`dotnet aspire starter`, `aspire template`, `blazor admin starter`, `aspnet core identity`, `mudblazor dashboard`, `postgresql aspire`, `minimal api starter`, `smtp4dev`, `ef core migrations`, `redis output cache`.',
        '`dotnet aspire starter`, `aspire template`, `blazor admin starter`, `aspnet core identity`, `mudblazor dashboard`, `database-backed aspire`, `minimal api starter`, `smtp4dev`, `ef core migrations`, `redis output cache`.')
    Write-Utf8NoBom $readmePath $readme
}
