// cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
// KHÔNG đặt đơn hay thu tiền.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var items = new List<object>();

// /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
app.MapGet("/health", () => Results.Json(new { service = "cart", status = "ok" }));
app.MapPost("/cart/items", (CartItem item) =>
{
    items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
    return Results.Created("/cart/items", new { items });
});

app.Run("http://localhost:5002");

record CartItem(string Sku, int? Qty);
