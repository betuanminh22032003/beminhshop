// cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
// KHÔNG đặt đơn hay thu tiền.
using Cart;

var config = Config.Load(defaultPort: 5002, defaultName: "cart");

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://localhost:{config.Port}");
var app = builder.Build();

var items = new List<object>();

// Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
   .AllowAnonymous();
app.MapPost("/cart/items", (CartItem item) =>
{
    items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
    return Results.Created("/cart/items", new { items });
});

Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
app.Run();

record CartItem(string Sku, int? Qty);
