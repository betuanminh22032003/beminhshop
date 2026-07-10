// payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
// KHÔNG quản lý sản phẩm hay giỏ hàng.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { service = "payment", status = "ok" }));

app.Run();
