// payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
// KHÔNG quản lý sản phẩm hay giỏ hàng.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment";

// Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)));

app.Run();
