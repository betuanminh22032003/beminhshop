// cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
// KHÔNG đặt đơn hay thu tiền.
using Cart;

var config = Config.Load(defaultPort: 5002, defaultName: "cart");

var builder = WebApplication.CreateBuilder(args);
// Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5002).
builder.WebHost.UseUrls($"http://0.0.0.0:{config.Port}");
var app = builder.Build();

var items = new List<object>();

// /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
app.MapGet("/health", () => Results.Json(new { service = config.ServiceName, status = "ok" }));
app.MapPost("/cart/items", (CartItem item) =>
{
    items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
    return Results.Created("/cart/items", new { items });
});

Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
// Địa chỉ service anh em tiêm từ env — trong compose là DNS theo tên service (http://catalog:3001), không localhost.
Console.WriteLine($"[{config.ServiceName}] catalog url = {config.CatalogUrl}");
app.Run();

record CartItem(string Sku, int? Qty);
