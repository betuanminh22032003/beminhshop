// catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
// KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
using Catalog;

var config = Config.Load(defaultPort: 5001, defaultName: "catalog");

var builder = WebApplication.CreateBuilder(args);
// Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env (config.Port).
builder.WebHost.UseUrls($"http://0.0.0.0:{config.Port}");
var app = builder.Build();

// Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
   .AllowAnonymous();

// Danh sách sản phẩm đã seed — shape { items, total }.
var products = new[]
{
    new { id = "sku-001", title = "Starter Mug", priceCents = 1200 },
    new { id = "sku-002", title = "Field Notebook", priceCents = 800 },
    new { id = "sku-003", title = "Enamel Pin", priceCents = 500 },
};
app.MapGet("/products", () => new { items = products, total = products.Length });

Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
Console.WriteLine($"[{config.ServiceName}] catalog db = {config.DatabaseUrl}");
app.Run();
