// order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
// KHÔNG thu tiền thẻ.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { service = "order", status = "ok" }));

app.Run();
