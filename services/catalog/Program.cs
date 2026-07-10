// catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
// KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { service = "catalog", status = "ok" }));

app.Run();
