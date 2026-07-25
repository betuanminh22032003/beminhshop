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

var builder = WebApplication.CreateBuilder(args);
// Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5003).
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
var app = builder.Build();

// /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
app.MapGet("/health", () => Results.Json(new { service = serviceName, status = "ok" }));

Console.WriteLine($"[{serviceName}] listening on :{port}");
Console.WriteLine($"[{serviceName}] catalog url = {catalogUrl}");
Console.WriteLine($"[{serviceName}] cart url = {cartUrl}");
app.Run();
