// catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
// KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
app.MapGet("/health", () => Results.Json(new { service = "catalog", status = "ok" }));
app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });

app.Run("http://localhost:5001");
