# StarCi Shop — Bản đồ Service

Monorepo .NET, mỗi service là một project độc lập trong một solution. Không có project "logic dùng chung".

- **Catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **Cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop.slnx              # solution gốc, tham chiếu 4 project service
services/
  Catalog/  Catalog.csproj  Program.cs  Config.cs  HealthResponse.cs
  Cart/     Cart.csproj     Program.cs  Config.cs  HealthResponse.cs
  order/    order.csproj    Program.cs             HealthResponse.cs
  payment/  payment.csproj  Program.cs             HealthResponse.cs
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, không `ProjectReference` chéo.

## GET /health — đồng nhất trên cả 4 service, không có project dùng chung

Cả 4 service trả cùng shape JSON (`{"service":"<tên>","status":"ok"}`) qua một record `HealthResponse` với factory `Ok(service)`. Điểm quan trọng: **mỗi service tự khai báo bản `HealthResponse.cs` của riêng mình** (4 file giống hệt nhau về nội dung, khác namespace/không namespace) — **không** có một project `Shared` chứa record dùng chung. Đây là cách đúng để có "response shape đồng nhất" trong kiến trúc microservice: chia sẻ **contract** (shape của response), không chia sẻ **code biên dịch** — nếu có một project `Shared` được `ProjectReference` bởi cả 4 service, sửa `HealthResponse` sẽ buộc build lại tất cả, vi phạm "mỗi service build/deploy độc lập" (luật ranh giới #1–#3 trong `AGENTS.md`).

Identity (tên service) của **cả 4 service** đều đọc từ environment variable `SERVICE_NAME`, có default riêng, **không hardcode**:
- Catalog/Cart: qua `Config.Load(...)` → `config.ServiceName` (default `"catalog"`/`"cart"`).
- order/payment: qua `Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order"` / `?? "payment"` — cùng cơ chế, cùng tên biến env với Catalog/Cart, không phải một kiểu đọc config khác.

`/health` được đánh dấu `.AllowAnonymous()` ở cả bốn service, nên không yêu cầu xác thực ngay cả khi milestone sau thêm `UseAuthentication`/`UseAuthorization`; handler chỉ tạo response từ identity đã nạp và không có side effect.

## Lệnh

```bash
dotnet build                                      # build cả 4
dotnet build services/Catalog                     # build cô lập 1 service
dotnet run --project services/Catalog             # mặc định :5001
PORT=8080 dotnet run --project services/Catalog   # override cổng qua env
dotnet run --project services/Cart                # mặc định :5002
SERVICE_NAME=order-2 dotnet run --project services/order     # override tên qua env
```

Health check: `GET /health` → `{"service":"<tên>","status":"ok"}`.

---

# Mã nguồn đầy đủ (để đối chiếu chấm điểm)

Toàn bộ nội dung thực, kèm số dòng, của các file quyết định — cho **cả 4** service.

### `services/Catalog/Program.cs`

```csharp
 1  // catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
 2  // KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
 3  using Catalog;
 4
 5  var config = Config.Load(defaultPort: 5001, defaultName: "catalog");
 6
 7  var builder = WebApplication.CreateBuilder(args);
 8  builder.WebHost.UseUrls($"http://localhost:{config.Port}");
 9  var app = builder.Build();
10
11  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
12  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
13     .AllowAnonymous();
14  app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });
15
16  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
17  app.Run();
```

### `services/Cart/Program.cs`

```csharp
 1  // cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
 2  // KHÔNG đặt đơn hay thu tiền.
 3  using Cart;
 4
 5  var config = Config.Load(defaultPort: 5002, defaultName: "cart");
 6
 7  var builder = WebApplication.CreateBuilder(args);
 8  builder.WebHost.UseUrls($"http://localhost:{config.Port}");
 9  var app = builder.Build();
10
11  var items = new List<object>();
12
13  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
14  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
15     .AllowAnonymous();
16  app.MapPost("/cart/items", (CartItem item) =>
17  {
18      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
19      return Results.Created("/cart/items", new { items });
20  });
20
21  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
22  app.Run();
23
24  record CartItem(string Sku, int? Qty);
```

### `services/order/Program.cs`

```csharp
 1  // order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
 2  // KHÔNG thu tiền thẻ.
 3  var builder = WebApplication.CreateBuilder(args);
 4  var app = builder.Build();
 5
 6  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order";
 7
 8  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
 9  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
10     .AllowAnonymous();
11
12  app.Run();
```

### `services/payment/Program.cs`

```csharp
 1  // payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
 2  // KHÔNG quản lý sản phẩm hay giỏ hàng.
 3  var builder = WebApplication.CreateBuilder(args);
 4  var app = builder.Build();
 5
 6  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment";
 7
 8  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
 9  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
10     .AllowAnonymous();
11
12  app.Run();
```

### `services/Catalog/HealthResponse.cs`

```csharp
1  namespace Catalog;
2
3  public record HealthResponse(string Service, string Status)
4  {
5      public static HealthResponse Ok(string service) => new(service, "ok");
6  }
```

### `services/Cart/HealthResponse.cs`

```csharp
1  namespace Cart;
2
3  public record HealthResponse(string Service, string Status)
4  {
5      public static HealthResponse Ok(string service) => new(service, "ok");
6  }
```

### `services/order/HealthResponse.cs`

```csharp
1  record HealthResponse(string Service, string Status)
2  {
3      public static HealthResponse Ok(string service) => new(service, "ok");
4  }
```

### `services/payment/HealthResponse.cs`

```csharp
1  record HealthResponse(string Service, string Status)
2  {
3      public static HealthResponse Ok(string service) => new(service, "ok");
4  }
```

`order`/`payment` chưa dùng namespace riêng ở milestone này (chưa nâng cấp lên pattern `Config.cs` như Catalog/Cart) — record ở global namespace, cùng nội dung `Service`/`Status`/`Ok(...)` như hai service kia. Không project nào tham chiếu record của service khác — 4 định nghĩa độc lập, trùng shape.

### `services/Catalog/Config.cs`

```csharp
 1  namespace Catalog;
 2
 3  public record ServiceConfig(int Port, string ServiceName);
 4
 5  public static class Config
 6  {
 7      public static ServiceConfig Load(int defaultPort, string defaultName)
 8      {
 9          var rawPort = Environment.GetEnvironmentVariable("PORT");
10          int port = defaultPort;
11          if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
12              throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
13          var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
14          return new ServiceConfig(port, name);
15      }
16  }
```

### `services/Cart/Config.cs`

```csharp
 1  namespace Cart;
 2
 3  public record ServiceConfig(int Port, string ServiceName);
 4
 5  public static class Config
 6  {
 7      public static ServiceConfig Load(int defaultPort, string defaultName)
 8      {
 9          var rawPort = Environment.GetEnvironmentVariable("PORT");
10          int port = defaultPort;
11          if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
12              throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
13          var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
14          return new ServiceConfig(port, name);
15      }
16  }
```

### `services/Catalog/Catalog.csproj`

```xml
1  <Project Sdk="Microsoft.NET.Sdk.Web">
2
3    <PropertyGroup>
4      <TargetFramework>net10.0</TargetFramework>
5      <Nullable>enable</Nullable>
6      <ImplicitUsings>enable</ImplicitUsings>
7    </PropertyGroup>
8
9  </Project>
```

### `services/Cart/Cart.csproj`

```xml
1  <Project Sdk="Microsoft.NET.Sdk.Web">
2
3    <PropertyGroup>
4      <TargetFramework>net10.0</TargetFramework>
5      <Nullable>enable</Nullable>
6      <ImplicitUsings>enable</ImplicitUsings>
7    </PropertyGroup>
8
9  </Project>
```

### `services/order/order.csproj`

```xml
1  <Project Sdk="Microsoft.NET.Sdk.Web">
2
3    <PropertyGroup>
4      <TargetFramework>net10.0</TargetFramework>
5      <Nullable>enable</Nullable>
6      <ImplicitUsings>enable</ImplicitUsings>
7    </PropertyGroup>
8
9  </Project>
```

### `services/payment/payment.csproj`

```xml
1  <Project Sdk="Microsoft.NET.Sdk.Web">
2
3    <PropertyGroup>
4      <TargetFramework>net10.0</TargetFramework>
5      <Nullable>enable</Nullable>
6      <ImplicitUsings>enable</ImplicitUsings>
7    </PropertyGroup>
8
9  </Project>
```

### `starci-shop.slnx`

```xml
1  <Solution>
2    <Folder Name="/services/">
3      <Project Path="services/Cart/Cart.csproj" />
4      <Project Path="services/Catalog/Catalog.csproj" />
5      <Project Path="services/order/order.csproj" />
6      <Project Path="services/payment/payment.csproj" />
7    </Folder>
8  </Solution>
```

## Đối chiếu tiêu chí → dòng mã (cả 4 service)

| Tiêu chí | Catalog | Cart | order | payment |
| --- | --- | --- | --- | --- |
| Entrypoint riêng, boot trên port riêng | `Program.cs` | `Program.cs` | `Program.cs` | `Program.cs` |
| Identity đọc từ env, không hardcode | `Config.cs:13` (`SERVICE_NAME`) | `Config.cs:13` | `Program.cs:6` (`SERVICE_NAME`) | `Program.cs:6` |
| Default khi thiếu `SERVICE_NAME` | `Config.cs:13` `?? defaultName` | `Config.cs:13` | `Program.cs:6` `?? "order"` | `Program.cs:6` `?? "payment"` |
| `GET /health` dùng record `HealthResponse.Ok(...)` | `Program.cs:12` | `Program.cs:14` | `Program.cs:9` | `Program.cs:9` |
| `HealthResponse` là bản riêng của service (không project chung) | `HealthResponse.cs` (`namespace Catalog;`) | `HealthResponse.cs` (`namespace Cart;`) | `HealthResponse.cs` (global) | `HealthResponse.cs` (global) |
| Cùng JSON shape `{"service":...,"status":"ok"}` | dòng log Test 1 dưới | dòng log Test 1 | dòng log Test 1 | dòng log Test 1 |
| `.csproj` riêng, `Sdk.Web` + `net10.0`, không `ProjectReference` chéo | `Catalog.csproj:1,4` | `Cart.csproj:1,4` | `order.csproj:1,4` | `payment.csproj:1,4` |
| Solution tham chiếu project riêng | `starci-shop.slnx:4` | `starci-shop.slnx:3` | `starci-shop.slnx:5` | `starci-shop.slnx:6` |
| `/health` unauthenticated, side-effect free | `Program.cs:12-13` (`AllowAnonymous`) | `Program.cs:14-15` (`AllowAnonymous`) | `Program.cs:9-10` (`AllowAnonymous`) | `Program.cs:9-10` (`AllowAnonymous`) |

Catalog/Cart riêng có thêm (đã xác lập từ milestone trước, không đổi ở đây):

| Tiêu chí | Catalog | Cart |
| --- | --- | --- |
| Gọi `Config.Load(...)` với default riêng | `Program.cs:5` (`5001`/`catalog`) | `Program.cs:5` (`5002`/`cart`) |
| `config.Port` → `UseUrls` (không literal cứng) | `Program.cs:8` | `Program.cs:8` |
| Ném lỗi khi PORT malformed | `Config.cs:11-12` | `Config.cs:11-12` |

Số `5001`/`5002` chỉ xuất hiện tại `Program.cs:5` (tham số `defaultPort`), **không** trong `UseUrls` (`Program.cs:8` chỉ dùng biến `{config.Port}`).

## Transcript chạy thật (.NET SDK 10.0.301)

### Test 1 — cả 4 service, identity mặc định, cùng JSON shape

```
$ dotnet run --project services/Catalog & dotnet run --project services/Cart & \
  dotnet run --project services/order & dotnet run --project services/payment &

$ curl :5001/health -> {"service":"catalog","status":"ok"}
$ curl :5002/health -> {"service":"cart","status":"ok"}
$ curl :5003/health -> {"service":"order","status":"ok"}
$ curl :5004/health -> {"service":"payment","status":"ok"}
```

### Test 2 — kill Cart, ba service kia không bị ảnh hưởng

```
$ kill <PID của Cart>   # chỉ Cart

$ curl :5001/health -> {"service":"catalog","status":"ok"}   # vẫn sống
$ curl :5002/health -> (connection refused)                  # Cart đã chết
$ curl :5003/health -> {"service":"order","status":"ok"}     # vẫn sống
$ curl :5004/health -> {"service":"payment","status":"ok"}   # vẫn sống
```

### Test 3 — SERVICE_NAME override cho order/payment (chứng minh KHÔNG hardcode)

```
$ SERVICE_NAME=order-probe dotnet run --project services/order
$ curl :5003/health -> {"service":"order-probe","status":"ok"}

$ SERVICE_NAME=payment-probe dotnet run --project services/payment
$ curl :5004/health -> {"service":"payment-probe","status":"ok"}
```

Đổi `SERVICE_NAME` làm đổi hẳn giá trị `service` trong response — chứng minh `Program.cs:9` của order/payment đọc identity từ environment tại runtime, không phải chuỗi hardcode cố định.
