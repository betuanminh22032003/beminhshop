// cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
// KHÔNG đặt đơn hay thu tiền.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { service = "cart", status = "ok" }));

app.Run();
