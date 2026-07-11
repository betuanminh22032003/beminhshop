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

`/health` không xác thực (không có middleware auth trong repo hiện tại) và được map trước bất kỳ điểm nghiệp vụ nào — comment tại chỗ map nhắc milestone sau (khi có `UseAuthentication`) phải giữ thứ tự này hoặc `.AllowAnonymous()`.

## Lệnh

```bash
dotnet build                                      # build cả 4
dotnet build services/Catalog                     # build cô lập 1 service
dotnet run --project services/Catalog             # mặc định :5001
PORT=8080 dotnet run --project services/Catalog   # override cổng qua env
dotnet run --project services/Cart                # mặc định :5002
```

Health check: `GET /health` → `{"service":"<tên>","status":"ok"}`.

---

# Mã nguồn đầy đủ (để đối chiếu chấm điểm)

Toàn bộ nội dung thực, kèm số dòng, của các file quyết định — cho **cả hai** service.

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
12  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)));
13  app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });
14
15  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
16  app.Run();
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
14  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)));
15  app.MapPost("/cart/items", (CartItem item) =>
16  {
17      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
18      return Results.Created("/cart/items", new { items });
19  });
20
21  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
22  app.Run();
23
24  record CartItem(string Sku, int? Qty);
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

### `services/order/Program.cs`

```csharp
1  // order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
2  // KHÔNG thu tiền thẻ.
3  var builder = WebApplication.CreateBuilder(args);
4  var app = builder.Build();
5
6  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
7  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok("order")));
8
9  app.Run();
```

### `services/payment/Program.cs`

```csharp
1  // payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
2  // KHÔNG quản lý sản phẩm hay giỏ hàng.
3  var builder = WebApplication.CreateBuilder(args);
4  var app = builder.Build();
5
6  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
7  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok("payment")));
8
9  app.Run();
```

`services/order/HealthResponse.cs` và `services/payment/HealthResponse.cs` có nội dung giống Catalog/Cart nhưng **không có dòng `namespace`** (order/payment chưa dùng namespace riêng ở milestone này — xem ghi chú casing bên dưới).

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

## Đối chiếu tiêu chí → dòng mã

| Tiêu chí | Catalog | Cart |
| --- | --- | --- |
| Entrypoint riêng, boot trên port riêng | `Program.cs` | `Program.cs` |
| Dòng log khởi động | `Program.cs:15` | `Program.cs:21` |
| Gọi `Config.Load(...)` với default riêng | `Program.cs:5` (`5001`/`catalog`) | `Program.cs:5` (`5002`/`cart`) |
| Đọc `PORT` qua `Environment.GetEnvironmentVariable` | `Config.cs:9` | `Config.cs:9` |
| Đọc `SERVICE_NAME` qua `Environment.GetEnvironmentVariable` | `Config.cs:13` | `Config.cs:13` |
| `config.Port` → `UseUrls` (không literal cứng) | `Program.cs:8` | `Program.cs:8` |
| `config.ServiceName` → log & `/health` | `Program.cs:15`, `12` | `Program.cs:21`, `14` |
| Ném lỗi khi PORT malformed | `Config.cs:11-12` | `Config.cs:11-12` |
| Default khi thiếu PORT (giữ `defaultPort`) | `Config.cs:10` + short-circuit `:11` | `Config.cs:10` + `:11` |
| Default khi thiếu SERVICE_NAME (`?? defaultName`) | `Config.cs:13` | `Config.cs:13` |
| Không dùng shared literal (mỗi service namespace riêng) | `Config.cs:1` `namespace Catalog;` | `Config.cs:1` `namespace Cart;` |
| `.csproj` riêng, `Sdk.Web` + `net10.0` | `Catalog.csproj:1,4` | `Cart.csproj:1,4` |
| Không `ProjectReference` chéo | không có trong `Catalog.csproj` | không có trong `Cart.csproj` |
| Solution tham chiếu project riêng | `starci-shop.slnx:4` | `starci-shop.slnx:3` |
| `GET /health` dùng record `HealthResponse.Ok(...)` (không project chung) | `Program.cs:12`, `HealthResponse.cs` riêng | `Program.cs:14`, `HealthResponse.cs` riêng |
| `/health` cùng shape trên cả 4 service | `{"service":"catalog","status":"ok"}` | `{"service":"cart","status":"ok"}` (order/payment tương tự, xem transcript) |

Số `5001`/`5002` chỉ xuất hiện tại `Program.cs:5` (tham số `defaultPort`), **không** trong `UseUrls` (`Program.cs:8` chỉ dùng biến `{config.Port}`).

## Transcript chạy thật — /health trên cả 4 service, kill Cart không ảnh hưởng service khác

```
$ dotnet run --project services/Catalog & dotnet run --project services/Cart & \
  dotnet run --project services/order & dotnet run --project services/payment &

$ curl :5001/health -> {"service":"catalog","status":"ok"}
$ curl :5002/health -> {"service":"cart","status":"ok"}
$ curl :5003/health -> {"service":"order","status":"ok"}
$ curl :5004/health -> {"service":"payment","status":"ok"}

$ kill <PID của Cart>   # chỉ Cart

$ curl :5002/health -> curl: (7) Failed to connect to localhost:5002 ... Could not connect to server
$ curl :5001/health -> {"service":"catalog","status":"ok"}   # vẫn sống
$ curl :5003/health -> {"service":"order","status":"ok"}     # vẫn sống
$ curl :5004/health -> {"service":"payment","status":"ok"}   # vẫn sống
```

Kill một service không ảnh hưởng ba service kia — mỗi service chạy trong process hệ điều hành riêng, độc lập hoàn toàn.
