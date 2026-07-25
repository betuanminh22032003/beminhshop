// payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
// KHÔNG quản lý sản phẩm hay giỏ hàng.
var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment";

// Cổng từ env như ba service kia (milestone image tái lập được: payment giờ cũng được
// đóng gói, nên không thể phụ thuộc launchSettings.json — file đó chỉ tồn tại ở dev).
var rawPort = Environment.GetEnvironmentVariable("PORT");
int port = 5004;
if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
    throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");

var builder = WebApplication.CreateBuilder(args);
// Bind 0.0.0.0 để container reachable qua -p.
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
var app = builder.Build();

// Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
   .AllowAnonymous();

Console.WriteLine($"[{serviceName}] listening on :{port}");
// APP_VERSION do image nướng vào lúc build (ARG GIT_SHA); chạy từ source thì là "dev".
Console.WriteLine($"[{serviceName}] version = {Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev"}");
app.Run();
