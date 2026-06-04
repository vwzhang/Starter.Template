using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Starter.ApiService.Data;

public sealed class CatalogDbContextFactory : IDesignTimeDbContextFactory<CatalogDbContext>
{
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
}
