using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Starter.Web.Data;

public sealed class ApplicationDbContextFactory : IDesignTimeDbContextFactory<ApplicationDbContext>
{
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
}
