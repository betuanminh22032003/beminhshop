namespace Cart;

public record ServiceConfig(int Port, string ServiceName, string CatalogUrl);

public static class Config
{
    public static ServiceConfig Load(int defaultPort, string defaultName)
    {
        var rawPort = Environment.GetEnvironmentVariable("PORT");
        int port = defaultPort;
        if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
            throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
        var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
        // Địa chỉ Catalog TIÊM lúc chạy: trong compose là http://catalog:3001 (DNS theo tên service),
        // ngoài compose mặc định localhost:5001. Không bao giờ hardcode host của service khác.
        var catalogUrl = Environment.GetEnvironmentVariable("CATALOG_URL")
                         ?? "http://localhost:5001";
        return new ServiceConfig(port, name, catalogUrl);
    }
}
