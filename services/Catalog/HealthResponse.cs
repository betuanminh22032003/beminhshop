namespace Catalog;

public record HealthResponse(string Service, string Status)
{
    public static HealthResponse Ok(string service) => new(service, "ok");
}
