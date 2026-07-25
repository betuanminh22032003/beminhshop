namespace Catalog;

public record ServiceConfig(int Port, string ServiceName, string DatabaseUrl);

public static class Config
{
    public static ServiceConfig Load(int defaultPort, string defaultName)
    {
        var rawPort = Environment.GetEnvironmentVariable("PORT");
        int port = defaultPort;
        if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
            throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
        var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
        // URL DB catalog được TIÊM lúc chạy (từ env), không bao giờ nướng vào image.
        // CATALOG_DATABASE_URL (riêng cho service) thắng DATABASE_URL (tên chuẩn compose dùng chung).
        var databaseUrl = Environment.GetEnvironmentVariable("CATALOG_DATABASE_URL")
                          ?? Environment.GetEnvironmentVariable("DATABASE_URL")
                          ?? "postgres://localhost:5432/catalog";
        return new ServiceConfig(port, name, databaseUrl);
    }
}
