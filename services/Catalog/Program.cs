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

// Sản phẩm sống trong Postgres — host là TÊN SERVICE compose ("db"), dữ liệu trên named volume
// pgdata nên còn nguyên sau docker compose down && up. Seed chỉ chạy khi bảng còn rỗng.
var store = new ProductStore(config.DatabaseUrl);
Console.WriteLine($"[{config.ServiceName}] catalog db = {config.DatabaseUrl}");
await store.InitializeAsync();

// Shape giữ nguyên { items, total } — hợp đồng đã chốt từ milestone container.
app.MapGet("/products", async () =>
{
    var items = await store.ListAsync();
    return new { items, total = items.Count };
});

Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
Console.WriteLine($"[{config.ServiceName}] products source = {(store.UsesDatabase ? "postgres" : "in-memory seed")}");
app.Run();
