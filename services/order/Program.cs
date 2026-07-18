// order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
// KHÔNG thu tiền thẻ.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
app.MapGet("/health", () => Results.Json(new { service = "order", status = "ok" }));

app.Run("http://localhost:5003");
