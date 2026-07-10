namespace Catalog;

public record ServiceConfig(int Port, string ServiceName);

public static class Config
{
    public static ServiceConfig Load(int defaultPort, string defaultName)
    {
        var rawPort = Environment.GetEnvironmentVariable("PORT");
        int port = defaultPort;
        if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
            throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
        var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
        return new ServiceConfig(port, name);
    }
}
