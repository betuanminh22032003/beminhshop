using System.Text.Json.Serialization;

// Shape liveness/readiness của riêng order: { service, status } khi khoẻ, thêm { error }
// khi không. Error bị bỏ khỏi JSON lúc null nên bản "ok" giữ đúng hợp đồng cũ
// {"service":"order","status":"ok"}.
record HealthResponse(
    string Service,
    string Status,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Error = null)
{
    public static HealthResponse Ok(string service) => new(service, "ok");

    /// <summary>DB không với tới được → 503, nói rõ lý do thay vì 200 giả.</summary>
    public static HealthResponse Unhealthy(string service, string error) =>
        new(service, "unhealthy", error);
}
