// catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
// KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
using Catalog;

var config = Config.Load(defaultPort: 5001, defaultName: "catalog");

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://localhost:{config.Port}");
var app = builder.Build();

app.MapGet("/health", () => new { service = config.ServiceName, status = "ok" });
app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });

Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
app.Run();
