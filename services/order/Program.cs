// order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
// KHÔNG thu tiền thẻ.
var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order";

var rawPort = Environment.GetEnvironmentVariable("PORT");
int port = 5003;
if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
    throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");

// Địa chỉ service anh em TIÊM lúc chạy: trong compose là DNS theo tên service
// (http://catalog:3001, http://cart:3002), ngoài compose mặc định localhost. Không hardcode.
var catalogUrl = Environment.GetEnvironmentVariable("CATALOG_URL") ?? "http://localhost:5001";
var cartUrl = Environment.GetEnvironmentVariable("CART_URL") ?? "http://localhost:5002";

// Địa chỉ Postgres cũng từ env: ORDER_DATABASE_URL ưu tiên hơn DATABASE_URL chung của
// compose (host là TÊN SERVICE "db"), ngoài compose mặc định localhost.
var databaseUrl = Environment.GetEnvironmentVariable("ORDER_DATABASE_URL")
    ?? Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "postgres://shop:shop@localhost:5432/shop";

var builder = WebApplication.CreateBuilder(args);
// Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5003).
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
var app = builder.Build();

await using var probe = new DatabaseProbe(databaseUrl);

// /health là readiness THẬT: mỗi lần gọi là một round-trip `SELECT 1` tới Postgres.
// DB sống  -> 200 {"service":"order","status":"ok"}
// DB chết  -> 503 {"service":"order","status":"unhealthy","error":...}
// Docker HEALTHCHECK và depends_on: condition: service_healthy dựa vào chính chỗ này,
// nên KHÔNG được trả "ok" cứng: một 200 giả làm orchestrator đẩy lưu lượng checkout
// vào service không có DB.
app.MapGet("/health", async (CancellationToken ct) =>
{
    try
    {
        await probe.PingAsync(ct);
        return Results.Json(HealthResponse.Ok(serviceName));
    }
    catch (Exception ex)
    {
        return Results.Json(HealthResponse.Unhealthy(serviceName, ex.Message), statusCode: 503);
    }
});

Console.WriteLine($"[{serviceName}] listening on :{port}");
Console.WriteLine($"[{serviceName}] catalog url = {catalogUrl}");
Console.WriteLine($"[{serviceName}] cart url = {cartUrl}");
// KHÔNG in databaseUrl: chuỗi có password.
Console.WriteLine($"[{serviceName}] health probe = SELECT 1 on postgres");
app.Run();
