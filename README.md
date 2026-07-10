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
  Catalog/  Catalog.csproj  Program.cs  Config.cs
  Cart/     Cart.csproj     Program.cs  Config.cs
  order/    order.csproj    Program.cs
  payment/  payment.csproj  Program.cs
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, không `ProjectReference` chéo.

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
11  app.MapGet("/health", () => new { service = config.ServiceName, status = "ok" });
12  app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });
13
14  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
15  app.Run();
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
13  app.MapGet("/health", () => new { service = config.ServiceName, status = "ok" });
14  app.MapPost("/cart/items", (CartItem item) =>
15  {
16      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
17      return Results.Created("/cart/items", new { items });
18  });
19
20  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
21  app.Run();
22
23  record CartItem(string Sku, int? Qty);
```

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
| Dòng log khởi động | `Program.cs:14` | `Program.cs:20` |
| Gọi `Config.Load(...)` với default riêng | `Program.cs:5` (`5001`/`catalog`) | `Program.cs:5` (`5002`/`cart`) |
| Đọc `PORT` qua `Environment.GetEnvironmentVariable` | `Config.cs:9` | `Config.cs:9` |
| Đọc `SERVICE_NAME` qua `Environment.GetEnvironmentVariable` | `Config.cs:13` | `Config.cs:13` |
| `config.Port` → `UseUrls` (không literal cứng) | `Program.cs:8` | `Program.cs:8` |
| `config.ServiceName` → log & `/health` | `Program.cs:14`, `11` | `Program.cs:20`, `13` |
| Ném lỗi khi PORT malformed | `Config.cs:11-12` | `Config.cs:11-12` |
| Default khi thiếu PORT (giữ `defaultPort`) | `Config.cs:10` + short-circuit `:11` | `Config.cs:10` + `:11` |
| Default khi thiếu SERVICE_NAME (`?? defaultName`) | `Config.cs:13` | `Config.cs:13` |
| Không dùng shared literal (mỗi service namespace riêng) | `Config.cs:1` `namespace Catalog;` | `Config.cs:1` `namespace Cart;` |
| `.csproj` riêng, `Sdk.Web` + `net10.0` | `Catalog.csproj:1,4` | `Cart.csproj:1,4` |
| Không `ProjectReference` chéo | không có trong `Catalog.csproj` | không có trong `Cart.csproj` |
| Solution tham chiếu project riêng | `starci-shop.slnx:4` | `starci-shop.slnx:3` |

Số `5001`/`5002` chỉ xuất hiện tại `Program.cs:5` (tham số `defaultPort`), **không** trong `UseUrls` (`Program.cs:8` chỉ dùng biến `{config.Port}`).
